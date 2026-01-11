# frozen_string_literal: true

module Installer
  # rbenv Ruby version manager installer with uninstall support
  class RbenvInstaller < Base
    RBENV_ROOT = ENV['RBENV_ROOT'] || File.expand_path('~/.rbenv')

    def initialize(config)
      super('rbenv')
      @config = config
      @ruby_versions = config[:ruby_versions] || []
      @default_version = config[:default_version]
      @global_gems = config[:global_gems] || []
      @plugins = config[:plugins] || []
    end

    def install
      total = 1 + @plugins.size + @ruby_versions.size + @global_gems.size
      progress.start(total)

      ensure_rbenv_installed
      install_plugins
      install_ruby_versions
      set_default_version if @default_version
      install_global_gems

      progress.complete
    end

    def uninstall(item)
      case item[:type]
      when 'rbenv'
        uninstall_rbenv
      when 'plugin'
        uninstall_plugin(item[:name])
      when 'ruby_version'
        uninstall_ruby_version(item[:name])
      when 'gem'
        uninstall_gem(item[:name], item[:ruby_version])
      end
    end

    def installed?(item)
      case item
      when Hash
        check_installed_by_type(item[:name], item[:type])
      when String
        ruby_version_installed?(item)
      end
    end

    private

    def ensure_rbenv_installed
      progress.item_started('rbenv')

      if rbenv_installed?
        progress.item_skipped('rbenv')
        return
      end

      # Install via Homebrew (preferred method)
      if Command.which('brew')
        result = Command.run('brew install rbenv ruby-build')
        unless result.success?
          raise CommandError, "Failed to install rbenv: #{result.stderr}"
        end
      else
        # Fallback to git clone
        install_rbenv_from_git
      end

      setup_shell_integration
      record_installation('rbenv', type: 'rbenv')
    end

    def install_rbenv_from_git
      Command.run!("git clone https://github.com/rbenv/rbenv.git #{RBENV_ROOT}")
      Command.run!("git clone https://github.com/rbenv/ruby-build.git #{RBENV_ROOT}/plugins/ruby-build")
    end

    def setup_shell_integration
      shell_config = detect_shell_config
      return unless shell_config

      init_lines = <<~SHELL

        # rbenv initialization
        export PATH="$HOME/.rbenv/bin:$PATH"
        eval "$(rbenv init -)"
      SHELL

      # Check if already configured
      return if File.exist?(shell_config) && File.read(shell_config).include?('rbenv init')

      File.open(shell_config, 'a') { |f| f.write(init_lines) }
      progress.log("Added rbenv to #{shell_config}")
    end

    def detect_shell_config
      home = ENV['HOME']
      configs = %w[.zshrc .bashrc .bash_profile]
      configs.map { |c| File.join(home, c) }.find { |f| File.exist?(f) }
    end

    def install_plugins
      default_plugins = [
        { name: 'ruby-build', repo: 'rbenv/ruby-build' },
        { name: 'rbenv-vars', repo: 'rbenv/rbenv-vars' }
      ]

      (default_plugins + @plugins).uniq { |p| p[:name] }.each do |plugin|
        name = plugin[:name]
        repo = plugin[:repo]

        progress.item_started(name)

        if plugin_installed?(name)
          progress.item_skipped(name)
          next
        end

        plugin_path = File.join(RBENV_ROOT, 'plugins', name)
        result = Command.run("git clone https://github.com/#{repo}.git #{plugin_path}")

        if result.success?
          record_installation(name, type: 'plugin', repo: repo)
        else
          progress.error("Failed to install plugin #{name}: #{result.stderr}")
        end
      end
    end

    def install_ruby_versions
      @ruby_versions.each do |version|
        version_str = version.to_s

        progress.item_started("Ruby #{version_str}")

        if ruby_version_installed?(version_str)
          progress.item_skipped("Ruby #{version_str}")
          next
        end

        # Use rbenv install with verbose output
        result = Command.run(
          "#{rbenv_bin} install #{version_str}",
          timeout: 1800 # 30 min timeout for compilation
        )

        if result.success?
          Command.run("#{rbenv_bin} rehash")
          record_installation(version_str, type: 'ruby_version')
        else
          progress.error("Failed to install Ruby #{version_str}: #{result.stderr}")
        end
      end
    end

    def set_default_version
      version_str = @default_version.to_s
      return unless ruby_version_installed?(version_str)

      result = Command.run("#{rbenv_bin} global #{version_str}")
      if result.success?
        progress.log("Set default Ruby version to #{version_str}")
      else
        progress.error("Failed to set default version: #{result.stderr}")
      end
    end

    def install_global_gems
      return if @global_gems.empty?
      return if @ruby_versions.empty?

      # Install gems for each Ruby version
      @ruby_versions.each do |version|
        version_str = version.to_s
        next unless ruby_version_installed?(version_str)

        @global_gems.each do |gem_spec|
          gem_name = gem_spec.is_a?(Hash) ? gem_spec[:name] : gem_spec
          gem_version = gem_spec.is_a?(Hash) ? gem_spec[:version] : nil

          progress.item_started("#{gem_name} (Ruby #{version_str})")

          if gem_installed?(gem_name, version_str)
            progress.item_skipped("#{gem_name} (Ruby #{version_str})")
            next
          end

          install_cmd = gem_version ? "#{gem_name}:#{gem_version}" : gem_name
          result = Command.run(
            "RBENV_VERSION=#{version_str} #{rbenv_bin} exec gem install #{install_cmd} --no-document"
          )

          if result.success?
            record_installation(gem_name, type: 'gem', ruby_version: version_str, version: gem_version)
          else
            progress.error("Failed to install gem #{gem_name}: #{result.stderr}")
          end
        end
      end
    end

    # Check methods
    def rbenv_installed?
      Command.which('rbenv') || File.exist?(File.join(RBENV_ROOT, 'bin', 'rbenv'))
    end

    def plugin_installed?(name)
      File.directory?(File.join(RBENV_ROOT, 'plugins', name))
    end

    def ruby_version_installed?(version)
      result = Command.run("#{rbenv_bin} versions --bare | grep -q '^#{version}$'")
      result.success?
    end

    def gem_installed?(name, ruby_version)
      result = Command.run(
        "RBENV_VERSION=#{ruby_version} #{rbenv_bin} exec gem list -i #{name} 2>/dev/null"
      )
      result.success?
    end

    def rbenv_bin
      Command.which('rbenv') || File.join(RBENV_ROOT, 'bin', 'rbenv')
    end

    # Uninstall methods
    def uninstall_rbenv
      if Command.which('brew')
        Command.run('brew uninstall rbenv ruby-build')
      end
      FileUtils.rm_rf(RBENV_ROOT)
    end

    def uninstall_plugin(name)
      FileUtils.rm_rf(File.join(RBENV_ROOT, 'plugins', name))
    end

    def uninstall_ruby_version(version)
      Command.run!("#{rbenv_bin} uninstall -f #{version}")
    end

    def uninstall_gem(name, ruby_version)
      Command.run("RBENV_VERSION=#{ruby_version} #{rbenv_bin} exec gem uninstall -x #{name}")
    end

    def check_installed_by_type(name, type)
      case type
      when 'rbenv'
        rbenv_installed?
      when 'plugin'
        plugin_installed?(name)
      when 'ruby_version'
        ruby_version_installed?(name)
      else
        false
      end
    end
  end

  Registry.register(:rbenv, RbenvInstaller,
    description: 'Install rbenv and Ruby versions',
    order: 15) # After Homebrew, before Codex
end

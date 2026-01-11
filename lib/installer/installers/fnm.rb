# frozen_string_literal: true

module Installer
  # fnm (Fast Node Manager) installer with rollback support
  # Using fnm over nvm for better performance and Homebrew support
  class FnmInstaller < Base
    FNM_DIR = ENV['FNM_DIR'] || File.expand_path('~/.fnm')

    def initialize(config)
      super('fnm')
      @config = config
      @node_versions = config[:node_versions] || []
      @default_version = config[:default_version]
      @global_packages = config[:global_packages] || []
    end

    def install
      total = 1 + @node_versions.size + @global_packages.size
      progress.start(total)

      ensure_fnm_installed
      install_node_versions
      set_default_version if @default_version
      install_global_packages

      progress.complete
    end

    def uninstall(item)
      case item[:type]
      when 'fnm'
        uninstall_fnm
      when 'node_version'
        uninstall_node_version(item[:name])
      when 'package'
        uninstall_package(item[:name], item[:node_version])
      end
    end

    def installed?(item)
      case item
      when Hash
        check_installed_by_type(item[:name], item[:type])
      when String
        node_version_installed?(item)
      end
    end

    private

    def ensure_fnm_installed
      progress.item_started('fnm')

      if fnm_installed?
        progress.item_skipped('fnm')
        return
      end

      if Command.which('brew')
        result = Command.run('brew install fnm')
        unless result.success?
          raise CommandError, "Failed to install fnm: #{result.stderr}"
        end
      else
        # Install via curl script
        result = Command.run('curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell')
        unless result.success?
          raise CommandError, "Failed to install fnm: #{result.stderr}"
        end
      end

      setup_shell_integration
      record_installation('fnm', type: 'fnm')
    end

    def setup_shell_integration
      shell_config = detect_shell_config
      return unless shell_config

      init_lines = <<~SHELL

        # fnm (Fast Node Manager) initialization
        eval "$(fnm env --use-on-cd)"
      SHELL

      return if File.exist?(shell_config) && File.read(shell_config).include?('fnm env')

      File.open(shell_config, 'a') { |f| f.write(init_lines) }
      progress.log("Added fnm to #{shell_config}")
    end

    def detect_shell_config
      home = ENV['HOME']
      configs = %w[.zshrc .bashrc .bash_profile]
      configs.map { |c| File.join(home, c) }.find { |f| File.exist?(f) }
    end

    def install_node_versions
      @node_versions.each do |version|
        version_str = normalize_version(version)

        progress.item_started("Node.js #{version_str}")

        if node_version_installed?(version_str)
          progress.item_skipped("Node.js #{version_str}")
          next
        end

        result = Command.run(
          "#{fnm_bin} install #{version_str}",
          timeout: 600 # 10 min timeout
        )

        if result.success?
          record_installation(version_str, type: 'node_version')
        else
          progress.error("Failed to install Node.js #{version_str}: #{result.stderr}")
        end
      end
    end

    def set_default_version
      version_str = normalize_version(@default_version)
      return unless node_version_installed?(version_str)

      result = Command.run("#{fnm_bin} default #{version_str}")
      if result.success?
        progress.log("Set default Node.js version to #{version_str}")
      else
        progress.error("Failed to set default version: #{result.stderr}")
      end
    end

    def install_global_packages
      return if @global_packages.empty?
      return if @node_versions.empty?

      # Install for default version only
      version_str = normalize_version(@default_version || @node_versions.first)
      return unless node_version_installed?(version_str)

      @global_packages.each do |pkg|
        pkg_name = pkg.is_a?(Hash) ? pkg[:name] : pkg
        pkg_version = pkg.is_a?(Hash) ? pkg[:version] : nil

        progress.item_started("#{pkg_name} (Node #{version_str})")

        if package_installed?(pkg_name, version_str)
          progress.item_skipped("#{pkg_name} (Node #{version_str})")
          next
        end

        install_pkg = pkg_version ? "#{pkg_name}@#{pkg_version}" : pkg_name
        result = Command.run(
          "#{fnm_bin} exec --using=#{version_str} npm install -g #{install_pkg}"
        )

        if result.success?
          record_installation(pkg_name, type: 'package', node_version: version_str, version: pkg_version)
        else
          progress.error("Failed to install #{pkg_name}: #{result.stderr}")
        end
      end
    end

    # Normalize version (handle lts aliases)
    def normalize_version(version)
      version.to_s.downcase
    end

    # Check methods
    def fnm_installed?
      Command.which('fnm').nil? == false
    end

    def node_version_installed?(version)
      result = Command.run("#{fnm_bin} list | grep -q '#{version}'")
      result.success?
    end

    def package_installed?(name, node_version)
      result = Command.run(
        "#{fnm_bin} exec --using=#{node_version} npm list -g --depth=0 2>/dev/null | grep -q ' #{name}@'"
      )
      result.success?
    end

    def fnm_bin
      Command.which('fnm') || File.join(FNM_DIR, 'fnm')
    end

    # Uninstall methods
    def uninstall_fnm
      Command.run('brew uninstall fnm') if Command.which('brew')
      FileUtils.rm_rf(FNM_DIR)
    end

    def uninstall_node_version(version)
      Command.run!("#{fnm_bin} uninstall #{version}")
    end

    def uninstall_package(name, node_version)
      Command.run("#{fnm_bin} exec --using=#{node_version} npm uninstall -g #{name}")
    end

    def check_installed_by_type(name, type)
      case type
      when 'fnm'
        fnm_installed?
      when 'node_version'
        node_version_installed?(name)
      else
        false
      end
    end
  end

  Registry.register(:fnm, FnmInstaller,
    description: 'Install fnm and Node.js versions',
    order: 17) # After pyenv
end

# frozen_string_literal: true

module Installer
  # pyenv Python version manager installer with rollback support
  class PyenvInstaller < Base
    PYENV_ROOT = ENV['PYENV_ROOT'] || File.expand_path('~/.pyenv')

    def initialize(config)
      super('pyenv')
      @config = config
      @python_versions = config[:python_versions] || []
      @default_version = config[:default_version]
      @global_packages = config[:global_packages] || []
      @plugins = config[:plugins] || []
    end

    def install
      total = 1 + @plugins.size + @python_versions.size + @global_packages.size
      progress.start(total)

      ensure_pyenv_installed
      install_plugins
      install_python_versions
      set_default_version if @default_version
      install_global_packages

      progress.complete
    end

    def uninstall(item)
      case item[:type]
      when 'pyenv'
        uninstall_pyenv
      when 'plugin'
        uninstall_plugin(item[:name])
      when 'python_version'
        uninstall_python_version(item[:name])
      when 'package'
        uninstall_package(item[:name], item[:python_version])
      end
    end

    def installed?(item)
      case item
      when Hash
        check_installed_by_type(item[:name], item[:type])
      when String
        python_version_installed?(item)
      end
    end

    private

    def ensure_pyenv_installed
      progress.item_started('pyenv')

      if pyenv_installed?
        progress.item_skipped('pyenv')
        return
      end

      if Command.which('brew')
        result = Command.run('brew install pyenv pyenv-virtualenv')
        unless result.success?
          raise CommandError, "Failed to install pyenv: #{result.stderr}"
        end
      else
        install_pyenv_from_git
      end

      setup_shell_integration
      record_installation('pyenv', type: 'pyenv')
    end

    def install_pyenv_from_git
      Command.run!("git clone https://github.com/pyenv/pyenv.git #{PYENV_ROOT}")
      Command.run!("git clone https://github.com/pyenv/pyenv-virtualenv.git #{PYENV_ROOT}/plugins/pyenv-virtualenv")
    end

    def setup_shell_integration
      shell_config = detect_shell_config
      return unless shell_config

      init_lines = <<~SHELL

        # pyenv initialization
        export PYENV_ROOT="$HOME/.pyenv"
        [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init -)"
        eval "$(pyenv virtualenv-init -)"
      SHELL

      return if File.exist?(shell_config) && File.read(shell_config).include?('pyenv init')

      File.open(shell_config, 'a') { |f| f.write(init_lines) }
      progress.log("Added pyenv to #{shell_config}")
    end

    def detect_shell_config
      home = ENV['HOME']
      configs = %w[.zshrc .bashrc .bash_profile]
      configs.map { |c| File.join(home, c) }.find { |f| File.exist?(f) }
    end

    def install_plugins
      default_plugins = [
        { name: 'pyenv-virtualenv', repo: 'pyenv/pyenv-virtualenv' }
      ]

      (default_plugins + @plugins).uniq { |p| p[:name] }.each do |plugin|
        name = plugin[:name]
        repo = plugin[:repo]

        progress.item_started(name)

        if plugin_installed?(name)
          progress.item_skipped(name)
          next
        end

        plugin_path = File.join(PYENV_ROOT, 'plugins', name)
        result = Command.run("git clone https://github.com/#{repo}.git #{plugin_path}")

        if result.success?
          record_installation(name, type: 'plugin', repo: repo)
        else
          progress.error("Failed to install plugin #{name}: #{result.stderr}")
        end
      end
    end

    def install_python_versions
      @python_versions.each do |version|
        version_str = version.to_s

        progress.item_started("Python #{version_str}")

        if python_version_installed?(version_str)
          progress.item_skipped("Python #{version_str}")
          next
        end

        result = Command.run(
          "#{pyenv_bin} install #{version_str}",
          timeout: 1800 # 30 min for compilation
        )

        if result.success?
          Command.run("#{pyenv_bin} rehash")
          record_installation(version_str, type: 'python_version')
        else
          progress.error("Failed to install Python #{version_str}: #{result.stderr}")
        end
      end
    end

    def set_default_version
      version_str = @default_version.to_s
      return unless python_version_installed?(version_str)

      result = Command.run("#{pyenv_bin} global #{version_str}")
      if result.success?
        progress.log("Set default Python version to #{version_str}")
      else
        progress.error("Failed to set default version: #{result.stderr}")
      end
    end

    def install_global_packages
      return if @global_packages.empty?
      return if @python_versions.empty?

      @python_versions.each do |version|
        version_str = version.to_s
        next unless python_version_installed?(version_str)

        @global_packages.each do |pkg|
          pkg_name = pkg.is_a?(Hash) ? pkg[:name] : pkg
          pkg_version = pkg.is_a?(Hash) ? pkg[:version] : nil

          progress.item_started("#{pkg_name} (Python #{version_str})")

          if package_installed?(pkg_name, version_str)
            progress.item_skipped("#{pkg_name} (Python #{version_str})")
            next
          end

          install_cmd = pkg_version ? "#{pkg_name}==#{pkg_version}" : pkg_name
          result = Command.run(
            "PYENV_VERSION=#{version_str} #{pyenv_bin} exec pip install #{install_cmd}"
          )

          if result.success?
            record_installation(pkg_name, type: 'package', python_version: version_str, version: pkg_version)
          else
            progress.error("Failed to install #{pkg_name}: #{result.stderr}")
          end
        end
      end
    end

    # Check methods
    def pyenv_installed?
      Command.which('pyenv') || File.exist?(File.join(PYENV_ROOT, 'bin', 'pyenv'))
    end

    def plugin_installed?(name)
      File.directory?(File.join(PYENV_ROOT, 'plugins', name))
    end

    def python_version_installed?(version)
      result = Command.run("#{pyenv_bin} versions --bare | grep -q '^#{version}$'")
      result.success?
    end

    def package_installed?(name, python_version)
      result = Command.run(
        "PYENV_VERSION=#{python_version} #{pyenv_bin} exec pip show #{name} 2>/dev/null"
      )
      result.success?
    end

    def pyenv_bin
      Command.which('pyenv') || File.join(PYENV_ROOT, 'bin', 'pyenv')
    end

    # Uninstall methods
    def uninstall_pyenv
      Command.run('brew uninstall pyenv pyenv-virtualenv') if Command.which('brew')
      FileUtils.rm_rf(PYENV_ROOT)
    end

    def uninstall_plugin(name)
      FileUtils.rm_rf(File.join(PYENV_ROOT, 'plugins', name))
    end

    def uninstall_python_version(version)
      Command.run!("#{pyenv_bin} uninstall -f #{version}")
    end

    def uninstall_package(name, python_version)
      Command.run("PYENV_VERSION=#{python_version} #{pyenv_bin} exec pip uninstall -y #{name}")
    end

    def check_installed_by_type(name, type)
      case type
      when 'pyenv'
        pyenv_installed?
      when 'plugin'
        plugin_installed?(name)
      when 'python_version'
        python_version_installed?(name)
      else
        false
      end
    end
  end

  Registry.register(:pyenv, PyenvInstaller,
    description: 'Install pyenv and Python versions',
    order: 16) # After rbenv
end

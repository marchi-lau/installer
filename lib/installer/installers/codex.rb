# frozen_string_literal: true

module Installer
  # Codex/Development tools installer with uninstall support
  # Handles VS Code extensions, npm global packages, and other dev tools
  class CodexInstaller < Base
    def initialize(config)
      super('codex')
      @config = config
      @vscode_extensions = config[:vscode_extensions] || []
      @npm_globals = config[:npm_globals] || []
      @pip_packages = config[:pip_packages] || []
      @custom_scripts = config[:custom_scripts] || []
    end

    def install
      total = @vscode_extensions.size + @npm_globals.size +
              @pip_packages.size + @custom_scripts.size
      progress.start(total)

      install_vscode_extensions
      install_npm_globals
      install_pip_packages
      run_custom_scripts

      progress.complete
    end

    def uninstall(item)
      case item[:type]
      when 'vscode_extension'
        uninstall_vscode_extension(item[:name])
      when 'npm_global'
        Command.run!("npm uninstall -g #{item[:name]}")
      when 'pip_package'
        Command.run!("pip3 uninstall -y #{item[:name]}")
      when 'custom_script'
        run_rollback_script(item)
      end
    end

    def installed?(item)
      case item
      when Hash
        check_installed_by_type(item[:name], item[:type])
      when String
        vscode_extension_installed?(item) ||
          npm_global_installed?(item) ||
          pip_package_installed?(item)
      end
    end

    private

    # VS Code Extensions
    def install_vscode_extensions
      return unless Command.which('code')

      @vscode_extensions.each do |ext|
        name = ext.is_a?(Hash) ? ext[:id] : ext

        progress.item_started(name)

        if vscode_extension_installed?(name)
          progress.item_skipped(name)
          next
        end

        result = Command.run("code --install-extension #{name}")
        if result.success?
          record_installation(name, type: 'vscode_extension')
        else
          progress.error("Failed to install extension #{name}: #{result.stderr}")
        end
      end
    end

    def uninstall_vscode_extension(name)
      Command.run!("code --uninstall-extension #{name}")
    end

    def vscode_extension_installed?(name)
      result = Command.run("code --list-extensions | grep -qi '^#{name}$'")
      result.success?
    end

    # NPM Global Packages
    def install_npm_globals
      return unless Command.which('npm')

      @npm_globals.each do |pkg|
        name = pkg.is_a?(Hash) ? pkg[:name] : pkg
        version = pkg.is_a?(Hash) ? pkg[:version] : nil
        install_name = version ? "#{name}@#{version}" : name

        progress.item_started(name)

        if npm_global_installed?(name)
          progress.item_skipped(name)
          next
        end

        result = Command.run("npm install -g #{install_name}")
        if result.success?
          record_installation(name, type: 'npm_global', version: version)
        else
          progress.error("Failed to install npm package #{name}: #{result.stderr}")
        end
      end
    end

    def npm_global_installed?(name)
      result = Command.run("npm list -g --depth=0 2>/dev/null | grep -q ' #{name}@'")
      result.success?
    end

    # Pip Packages
    def install_pip_packages
      return unless Command.which('pip3')

      @pip_packages.each do |pkg|
        name = pkg.is_a?(Hash) ? pkg[:name] : pkg
        version = pkg.is_a?(Hash) ? pkg[:version] : nil
        install_name = version ? "#{name}==#{version}" : name

        progress.item_started(name)

        if pip_package_installed?(name)
          progress.item_skipped(name)
          next
        end

        result = Command.run("pip3 install --user #{install_name}")
        if result.success?
          record_installation(name, type: 'pip_package', version: version)
        else
          progress.error("Failed to install pip package #{name}: #{result.stderr}")
        end
      end
    end

    def pip_package_installed?(name)
      result = Command.run("pip3 show #{name} 2>/dev/null")
      result.success?
    end

    # Custom Scripts
    def run_custom_scripts
      @custom_scripts.each do |script|
        name = script[:name] || 'Custom Script'
        install_cmd = script[:install]
        rollback_cmd = script[:rollback]
        check_cmd = script[:check]

        progress.item_started(name)

        if check_cmd && script_check_passes?(check_cmd)
          progress.item_skipped(name)
          next
        end

        result = Command.run(install_cmd)
        if result.success?
          record_installation(name,
            type: 'custom_script',
            rollback_cmd: rollback_cmd)
        else
          progress.error("Failed to run #{name}: #{result.stderr}")
        end
      end
    end

    def script_check_passes?(check_cmd)
      result = Command.run(check_cmd)
      result.success?
    end

    def run_rollback_script(item)
      return unless item[:rollback_cmd]
      Command.run!(item[:rollback_cmd])
    end

    def check_installed_by_type(name, type)
      case type
      when 'vscode_extension'
        vscode_extension_installed?(name)
      when 'npm_global'
        npm_global_installed?(name)
      when 'pip_package'
        pip_package_installed?(name)
      else
        false
      end
    end
  end

  Registry.register(:codex, CodexInstaller,
    description: 'Install development tools and extensions',
    order: 20)
end

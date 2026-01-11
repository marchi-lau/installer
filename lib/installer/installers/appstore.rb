# frozen_string_literal: true

module Installer
  # Mac App Store installer using mas CLI with uninstall support
  class AppStoreInstaller < Base
    def initialize(config)
      super('appstore')
      @config = config
      @apps = config[:apps] || []
      @require_signin = config.fetch(:require_signin, true)
    end

    def install
      ensure_mas_installed
      check_signin if @require_signin

      progress.start(@apps.size)

      @apps.each do |app|
        app_id = app[:id].to_s
        app_name = app[:name] || app_id

        progress.item_started(app_name)

        if app_installed?(app_id)
          progress.item_skipped(app_name)
          next
        end

        result = Command.run("mas install #{app_id}")
        if result.success?
          record_installation(app_name, type: 'appstore', app_id: app_id)
        else
          progress.error("Failed to install #{app_name}: #{result.stderr}")
        end
      end

      progress.complete
    end

    def uninstall(item)
      # Note: mas doesn't support uninstall directly
      # Apps must be manually removed from /Applications
      app_path = "/Applications/#{item[:name]}.app"
      if File.exist?(app_path)
        Command.run!("rm -rf '#{app_path}'")
      else
        progress.log("#{item[:name]} not found in /Applications, may need manual removal")
      end
    end

    def installed?(item)
      app_id = item.is_a?(Hash) ? item[:app_id] || item[:id] : item
      app_installed?(app_id.to_s)
    end

    private

    def ensure_mas_installed
      return if Command.which('mas')

      progress.log('mas CLI not found. Installing via Homebrew...')
      result = Command.run('brew install mas')
      unless result.success?
        raise CommandError, 'Failed to install mas CLI'
      end
    end

    def check_signin
      result = Command.run('mas account')
      unless result.success?
        progress.log('Not signed into App Store')
        progress.log('Please sign in to the App Store app and run again')
        raise CommandError, 'App Store sign-in required'
      end
      progress.log("Signed in as: #{result.stdout.strip}")
    end

    def app_installed?(app_id)
      result = Command.run("mas list | grep -q '^#{app_id} '")
      result.success?
    end
  end

  Registry.register(:appstore, AppStoreInstaller,
    description: 'Install apps from the Mac App Store',
    dependencies: %w[brew],
    order: 30)
end

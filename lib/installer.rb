# frozen_string_literal: true

require_relative 'installer/progress'
require_relative 'installer/command'
require_relative 'installer/base'
require_relative 'installer/registry'
require_relative 'installer/lockfile'
require_relative 'installer/scanner'
require_relative 'installer/notifier'
require_relative 'installer/logger'

# Load all installers
Dir[File.join(__dir__, 'installer', 'installers', '*.rb')].each do |file|
  require file
end

module Installer
  VERSION = '1.0.0'

  class << self
    def run_all(config)
      orchestrator = Orchestrator.new(config)
      orchestrator.run
    end

    def uninstall_all(config)
      orchestrator = Orchestrator.new(config)
      orchestrator.uninstall
    end
  end

  # Orchestrates multiple installers with dependency resolution
  class Orchestrator
    def initialize(config)
      @config = config
      @completed = []
      @failed = []
    end

    def run
      Lockfile.acquire!
      start_logging('install')

      puts banner('macOS Setup Installer')
      puts "Version: #{VERSION}"
      puts "Started at: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
      log_file = Logger.instance.log_file
      puts "Log file: #{log_file}" if log_file
      puts

      Logger.info("Starting installation", component: 'orchestrator')
      check_system_requirements

      Registry.all.each do |name, entry|
        next unless @config.dig(name, :enabled)

        run_installer(name, entry)
      end

      print_summary
      Logger.end_session(success: @failed.empty?)
      @failed.empty?
    rescue Lockfile::AlreadyRunningError => e
      Logger.error(e.message, component: 'lockfile')
      puts "\e[31mError: #{e.message}\e[0m"
      puts "Wait for the other process to finish or remove the lock file:"
      puts "  rm #{Lockfile::LOCK_PATH}"
      false
    end

    def uninstall
      Lockfile.acquire!

      puts banner('Uninstalling Components')

      @completed.reverse.each do |name|
        installer = Registry.create(name, @config[name])
        installer.uninstall_all
      rescue StandardError => e
        puts "Failed to uninstall #{name}: #{e.message}"
      end
    rescue Lockfile::AlreadyRunningError => e
      puts "\e[31mError: #{e.message}\e[0m"
      false
    end

    private

    def check_system_requirements
      unless Command.macos?
        puts "Warning: Not running on macOS. Some installers may not work."
        puts
      end

      if Command.macos?
        puts "macOS Version: #{Command.macos_version}"
        puts
      end
    end

    def run_installer(name, entry)
      missing_deps = Registry.check_dependencies(name)
      unless missing_deps.empty?
        Logger.warn("Skipping #{name}: missing dependencies #{missing_deps.join(', ')}", component: name.to_s)
        puts "Skipping #{name}: missing dependencies #{missing_deps.join(', ')}"
        return
      end

      Logger.info("Starting #{name}", component: name.to_s)
      installer = entry[:class].new(@config[name])
      installer.install
      @completed << name
      Logger.info("Completed #{name}", component: name.to_s)
    rescue StandardError => e
      @failed << { name: name, error: e.message }
      Logger.error("#{name} failed: #{e.message}", component: name.to_s)
      Logger.debug(e.backtrace.join("\n"), component: name.to_s) if e.backtrace
      puts "Error in #{name}: #{e.message}"

      if @config[:halt_on_error]
        puts "Halting due to error. Uninstalling..."
        uninstall
        exit 1
      end
    end

    def start_logging(session_name)
      if @config.fetch(:logging, true)
        Logger.instance.start_session(session_name)
        Logger.clean_old_logs(keep: @config.fetch(:log_retention, 10))
      else
        Logger.instance.disable!
      end
    end

    def print_summary
      puts banner('Installation Summary')
      puts "Completed: #{@completed.size} installers"
      puts "Failed: #{@failed.size} installers"

      unless @failed.empty?
        puts "\nFailed installers:"
        @failed.each do |f|
          puts "  - #{f[:name]}: #{f[:error]}"
        end
      end

      # Send notification
      send_notification
    end

    def send_notification
      return unless @config.fetch(:notifications, true)

      if @failed.empty?
        Notifier.success("Installed #{@completed.size} components successfully!")
      else
        Notifier.error("#{@failed.size} components failed. Check terminal for details.")
      end
    end

    def banner(title)
      line = '═' * 50
      "\n#{line}\n  #{title}\n#{line}"
    end
  end
end

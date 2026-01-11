# frozen_string_literal: true

require_relative 'installer/progress'
require_relative 'installer/command'
require_relative 'installer/base'
require_relative 'installer/registry'

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

    def rollback_all(config)
      orchestrator = Orchestrator.new(config)
      orchestrator.rollback
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
      puts banner('macOS Setup Installer')
      puts "Version: #{VERSION}"
      puts "Started at: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
      puts

      check_system_requirements

      Registry.all.each do |name, entry|
        next unless @config.dig(name, :enabled)

        run_installer(name, entry)
      end

      print_summary
      @failed.empty?
    end

    def rollback
      puts banner('Rolling Back Installation')

      @completed.reverse.each do |name|
        installer = Registry.create(name, @config[name])
        installer.rollback
      rescue StandardError => e
        puts "Failed to rollback #{name}: #{e.message}"
      end
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
        puts "Skipping #{name}: missing dependencies #{missing_deps.join(', ')}"
        return
      end

      installer = entry[:class].new(@config[name])
      installer.install
      @completed << name
    rescue StandardError => e
      @failed << { name: name, error: e.message }
      puts "Error in #{name}: #{e.message}"

      if @config[:halt_on_error]
        puts "Halting due to error. Rolling back..."
        rollback
        exit 1
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
    end

    def banner(title)
      line = '═' * 50
      "\n#{line}\n  #{title}\n#{line}"
    end
  end
end

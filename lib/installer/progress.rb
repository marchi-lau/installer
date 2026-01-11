# frozen_string_literal: true

module Installer
  # Progress tracking and display with colored output
  class Progress
    COLORS = {
      reset: "\e[0m",
      bold: "\e[1m",
      red: "\e[31m",
      green: "\e[32m",
      yellow: "\e[33m",
      blue: "\e[34m",
      magenta: "\e[35m",
      cyan: "\e[36m"
    }.freeze

    ICONS = {
      start: '▶',
      complete: '✓',
      skip: '○',
      error: '✗',
      rollback: '↺',
      progress: '→'
    }.freeze

    attr_reader :task_name, :total, :current, :start_time

    def initialize(task_name)
      @task_name = task_name
      @total = 0
      @current = 0
      @start_time = nil
      @errors = []
    end

    def start(total_items)
      @total = total_items
      @current = 0
      @start_time = Time.now
      @errors = []

      puts colorize("\n#{ICONS[:start]} Starting #{task_name}", :cyan, :bold)
      puts colorize("  #{total_items} items to process", :cyan)
      puts separator
    end

    def item_started(name)
      @current += 1
      print colorize("  #{ICONS[:progress]} [#{progress_bar}] ", :blue)
      print colorize("(#{@current}/#{@total}) ", :yellow)
      puts "Installing #{name}..."
    end

    def item_completed(name)
      puts colorize("    #{ICONS[:complete]} #{name} installed successfully", :green)
    end

    def item_skipped(name)
      @current += 1
      print colorize("  #{ICONS[:skip]} [#{progress_bar}] ", :blue)
      print colorize("(#{@current}/#{@total}) ", :yellow)
      puts colorize("#{name} already installed, skipping", :yellow)
    end

    def item_rolled_back(name)
      puts colorize("    #{ICONS[:rollback]} #{name} removed", :magenta)
    end

    def error(message)
      @errors << message
      puts colorize("    #{ICONS[:error]} #{message}", :red)
    end

    def log(message)
      puts colorize("  #{ICONS[:progress]} #{message}", :blue)
    end

    def complete
      duration = Time.now - @start_time
      puts separator
      puts colorize("#{ICONS[:complete]} #{task_name} completed!", :green, :bold)
      puts colorize("  Duration: #{format_duration(duration)}", :cyan)
      puts colorize("  Processed: #{@current}/#{@total} items", :cyan)
      puts colorize("  Errors: #{@errors.size}", @errors.empty? ? :green : :red)
      puts
    end

    def start_rollback
      puts colorize("\n#{ICONS[:rollback]} Starting rollback for #{task_name}", :magenta, :bold)
      puts separator
    end

    def complete_rollback
      puts separator
      puts colorize("#{ICONS[:complete]} Rollback completed for #{task_name}", :magenta, :bold)
      puts
    end

    private

    def progress_bar(width = 20)
      return '─' * width if @total.zero?

      filled = (@current.to_f / @total * width).round
      empty = width - filled
      "█" * filled + "░" * empty
    end

    def separator
      colorize('─' * 50, :blue)
    end

    def format_duration(seconds)
      if seconds < 60
        "#{seconds.round(1)}s"
      elsif seconds < 3600
        "#{(seconds / 60).floor}m #{(seconds % 60).round}s"
      else
        "#{(seconds / 3600).floor}h #{((seconds % 3600) / 60).floor}m"
      end
    end

    def colorize(text, *styles)
      return text unless $stdout.tty?

      codes = styles.map { |s| COLORS[s] }.compact.join
      "#{codes}#{text}#{COLORS[:reset]}"
    end
  end
end

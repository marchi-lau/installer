# frozen_string_literal: true

require 'fileutils'
require 'time'

module Installer
  # File-based logging for debugging and audit trail
  class Logger
    LOGS_DIR = File.join(Base::STATE_DIR, 'logs')

    LOG_LEVELS = {
      debug: 0,
      info: 1,
      warn: 2,
      error: 3
    }.freeze

    class << self
      def instance
        @instance ||= new
      end

      def method_missing(method, *args, &block)
        if instance.respond_to?(method)
          instance.send(method, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method, include_private = false)
        instance.respond_to?(method) || super
      end
    end

    attr_reader :log_file, :level

    def initialize(level: :info)
      @level = level
      @log_file = nil
      @enabled = true
    end

    def enable!
      @enabled = true
    end

    def disable!
      @enabled = false
    end

    def enabled?
      @enabled
    end

    def start_session(name = 'install')
      return unless @enabled

      ensure_logs_dir
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      @log_file = File.join(LOGS_DIR, "#{name}_#{timestamp}.log")

      write_header(name)
      @log_file
    end

    def end_session(success: true)
      return unless @enabled && @log_file

      info("Session ended: #{success ? 'SUCCESS' : 'FAILED'}")
      info("=" * 60)
      @log_file = nil
    end

    def debug(message, component: nil)
      log(:debug, message, component: component)
    end

    def info(message, component: nil)
      log(:info, message, component: component)
    end

    def warn(message, component: nil)
      log(:warn, message, component: component)
    end

    def error(message, component: nil)
      log(:error, message, component: component)
    end

    def command(cmd, result)
      return unless @enabled && @log_file

      debug("Command: #{cmd}", component: 'shell')
      debug("Exit code: #{result.exit_code}", component: 'shell')

      if result.stdout && !result.stdout.empty?
        result.stdout.each_line { |line| debug("  stdout: #{line.chomp}", component: 'shell') }
      end

      if result.stderr && !result.stderr.empty?
        result.stderr.each_line { |line| debug("  stderr: #{line.chomp}", component: 'shell') }
      end
    end

    def list_logs
      return [] unless Dir.exist?(LOGS_DIR)

      Dir.glob(File.join(LOGS_DIR, '*.log')).sort.reverse
    end

    def tail(lines: 50)
      return nil unless @log_file && File.exist?(@log_file)

      content = File.readlines(@log_file)
      content.last(lines).join
    end

    def clean_old_logs(keep: 10)
      logs = list_logs
      return if logs.size <= keep

      logs[keep..].each do |log|
        FileUtils.rm_f(log)
      end
    end

    private

    def ensure_logs_dir
      FileUtils.mkdir_p(LOGS_DIR)
    end

    def write_header(name)
      lines = [
        "=" * 60,
        "macOS Installer Log",
        "Session: #{name}",
        "Started: #{Time.now.iso8601}",
        "Version: #{VERSION}",
        "Ruby: #{RUBY_VERSION}",
        "Platform: #{RUBY_PLATFORM}",
        "=" * 60,
        ""
      ]

      File.write(@log_file, lines.join("\n"))
    end

    def log(level, message, component: nil)
      return unless @enabled && @log_file
      return if LOG_LEVELS[level] < LOG_LEVELS[@level]

      timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S.%L')
      level_str = level.to_s.upcase.ljust(5)
      component_str = component ? "[#{component}] " : ''

      line = "#{timestamp} #{level_str} #{component_str}#{message}\n"

      File.open(@log_file, 'a') { |f| f.write(line) }
    end
  end
end

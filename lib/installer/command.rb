# frozen_string_literal: true

require 'open3'

module Installer
  # Safe command execution with output capture and error handling
  class Command
    Result = Struct.new(:success, :stdout, :stderr, :exit_code, keyword_init: true) do
      def success?
        success
      end
    end

    class << self
      def run(command, env: {}, timeout: nil, capture: true)
        if capture
          run_captured(command, env: env, timeout: timeout)
        else
          run_interactive(command, env: env)
        end
      end

      def run!(command, env: {}, timeout: nil, capture: true)
        result = run(command, env: env, timeout: timeout, capture: capture)
        unless result.success?
          raise CommandError, "Command failed: #{command}\n#{result.stderr}"
        end
        result
      end

      def which(executable)
        result = run("which #{executable}")
        result.success? ? result.stdout.strip : nil
      end

      def macos?
        RUBY_PLATFORM.include?('darwin')
      end

      def macos_version
        return nil unless macos?
        result = run('sw_vers -productVersion')
        result.success? ? result.stdout.strip : nil
      end

      private

      def run_captured(command, env:, timeout:)
        stdout, stderr, status = nil

        if timeout
          Timeout.timeout(timeout) do
            stdout, stderr, status = Open3.capture3(env, command)
          end
        else
          stdout, stderr, status = Open3.capture3(env, command)
        end

        Result.new(
          success: status.success?,
          stdout: stdout,
          stderr: stderr,
          exit_code: status.exitstatus
        )
      rescue Timeout::Error
        Result.new(
          success: false,
          stdout: '',
          stderr: 'Command timed out',
          exit_code: -1
        )
      end

      def run_interactive(command, env:)
        pid = spawn(env, command)
        _, status = Process.wait2(pid)

        Result.new(
          success: status.success?,
          stdout: '',
          stderr: '',
          exit_code: status.exitstatus
        )
      end
    end
  end

  class CommandError < StandardError; end
end

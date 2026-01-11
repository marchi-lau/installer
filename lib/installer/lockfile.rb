# frozen_string_literal: true

module Installer
  # Prevents concurrent installer runs using a PID-based lockfile
  class Lockfile
    LOCK_PATH = File.join(Base::STATE_DIR, '.installer.lock')

    class AlreadyRunningError < StandardError; end

    class << self
      def acquire!
        ensure_state_dir

        if locked?
          pid, started_at = read_lock
          raise AlreadyRunningError,
            "Installer already running (PID #{pid}, started #{started_at})"
        end

        write_lock
        register_cleanup
        true
      end

      def release
        FileUtils.rm_f(LOCK_PATH)
      end

      def locked?
        return false unless File.exist?(LOCK_PATH)

        pid, = read_lock
        process_running?(pid)
      rescue StandardError
        false
      end

      def with_lock
        acquire!
        yield
      ensure
        release
      end

      private

      def ensure_state_dir
        FileUtils.mkdir_p(Base::STATE_DIR)
      end

      def write_lock
        lock_data = {
          pid: Process.pid,
          started_at: Time.now.iso8601,
          command: $PROGRAM_NAME
        }
        File.write(LOCK_PATH, JSON.pretty_generate(lock_data))
      end

      def read_lock
        data = JSON.parse(File.read(LOCK_PATH), symbolize_names: true)
        [data[:pid], data[:started_at]]
      rescue JSON::ParserError
        # Legacy format: just PID
        [File.read(LOCK_PATH).strip.to_i, 'unknown']
      end

      def process_running?(pid)
        return false unless pid.positive?

        Process.kill(0, pid)
        true
      rescue Errno::ESRCH # No such process
        false
      rescue Errno::EPERM # Permission denied = process exists
        true
      end

      def register_cleanup
        # Clean up on normal exit
        at_exit { release }

        # Clean up on signals
        %w[INT TERM].each do |signal|
          previous_handler = Signal.trap(signal) do
            release
            previous_handler&.call if previous_handler.is_a?(Proc)
            exit 1
          end
        end
      end
    end
  end
end

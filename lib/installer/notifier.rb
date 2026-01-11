# frozen_string_literal: true

module Installer
  # macOS notifications via terminal-notifier or osascript
  class Notifier
    class << self
      def notify(title:, message:, sound: 'default', group: 'macos-installer')
        return unless Command.macos?

        if terminal_notifier_available?
          notify_via_terminal_notifier(title, message, sound, group)
        else
          notify_via_osascript(title, message, sound)
        end
      end

      def success(message)
        notify(
          title: 'Installation Complete',
          message: message,
          sound: 'Glass'
        )
      end

      def error(message)
        notify(
          title: 'Installation Failed',
          message: message,
          sound: 'Basso'
        )
      end

      def info(message)
        notify(
          title: 'macOS Installer',
          message: message,
          sound: 'Pop'
        )
      end

      private

      def terminal_notifier_available?
        @terminal_notifier_available ||= Command.which('terminal-notifier')
      end

      def notify_via_terminal_notifier(title, message, sound, group)
        cmd = [
          'terminal-notifier',
          "-title '#{escape(title)}'",
          "-message '#{escape(message)}'",
          "-sound #{sound}",
          "-group #{group}",
          "-appIcon https://raw.githubusercontent.com/Homebrew/brew/master/docs/assets/img/homebrew.svg"
        ].join(' ')

        Command.run(cmd)
      end

      def notify_via_osascript(title, message, sound)
        script = <<~APPLESCRIPT
          display notification "#{escape(message)}" with title "#{escape(title)}" sound name "#{sound}"
        APPLESCRIPT

        Command.run("osascript -e '#{script}'")
      end

      def escape(str)
        str.to_s.gsub("'", "'\\''").gsub('"', '\\"')
      end
    end
  end
end

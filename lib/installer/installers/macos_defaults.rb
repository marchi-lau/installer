# frozen_string_literal: true

module Installer
  # macOS system preferences via `defaults write`
  class MacosDefaultsInstaller < Base
    # Common presets that can be enabled
    PRESETS = {
      developer: [
        # Finder: show hidden files
        { domain: 'com.apple.finder', key: 'AppleShowAllFiles', type: 'bool', value: true },
        # Finder: show all file extensions
        { domain: 'NSGlobalDomain', key: 'AppleShowAllExtensions', type: 'bool', value: true },
        # Finder: show path bar
        { domain: 'com.apple.finder', key: 'ShowPathbar', type: 'bool', value: true },
        # Finder: show status bar
        { domain: 'com.apple.finder', key: 'ShowStatusBar', type: 'bool', value: true },
        # Disable .DS_Store on network volumes
        { domain: 'com.apple.desktopservices', key: 'DSDontWriteNetworkStores', type: 'bool', value: true },
        # Disable .DS_Store on USB volumes
        { domain: 'com.apple.desktopservices', key: 'DSDontWriteUSBStores', type: 'bool', value: true },
        # Enable key repeat (disable press-and-hold)
        { domain: 'NSGlobalDomain', key: 'ApplePressAndHoldEnabled', type: 'bool', value: false },
        # Fast key repeat rate
        { domain: 'NSGlobalDomain', key: 'KeyRepeat', type: 'int', value: 2 },
        # Short delay until key repeat
        { domain: 'NSGlobalDomain', key: 'InitialKeyRepeat', type: 'int', value: 15 },
        # Save screenshots to Desktop
        { domain: 'com.apple.screencapture', key: 'location', type: 'string', value: '~/Desktop' },
        # Save screenshots as PNG
        { domain: 'com.apple.screencapture', key: 'type', type: 'string', value: 'png' }
      ],
      dock: [
        # Auto-hide Dock
        { domain: 'com.apple.dock', key: 'autohide', type: 'bool', value: true },
        # Remove auto-hide delay
        { domain: 'com.apple.dock', key: 'autohide-delay', type: 'float', value: 0 },
        # Fast auto-hide animation
        { domain: 'com.apple.dock', key: 'autohide-time-modifier', type: 'float', value: 0.3 },
        # Minimize windows to application icon
        { domain: 'com.apple.dock', key: 'minimize-to-application', type: 'bool', value: true },
        # Don't show recent apps
        { domain: 'com.apple.dock', key: 'show-recents', type: 'bool', value: false },
        # Set Dock icon size
        { domain: 'com.apple.dock', key: 'tilesize', type: 'int', value: 48 }
      ],
      trackpad: [
        # Enable tap to click
        { domain: 'com.apple.AppleMultitouchTrackpad', key: 'Clicking', type: 'bool', value: true },
        { domain: 'com.apple.driver.AppleBluetoothMultitouch.trackpad', key: 'Clicking', type: 'bool', value: true },
        # Enable three-finger drag
        { domain: 'com.apple.AppleMultitouchTrackpad', key: 'TrackpadThreeFingerDrag', type: 'bool', value: true }
      ],
      safari: [
        # Show full URL
        { domain: 'com.apple.Safari', key: 'ShowFullURLInSmartSearchField', type: 'bool', value: true },
        # Enable develop menu
        { domain: 'com.apple.Safari', key: 'IncludeDevelopMenu', type: 'bool', value: true },
        # Enable web inspector
        { domain: 'com.apple.Safari', key: 'WebKitDeveloperExtrasEnabledPreferenceKey', type: 'bool', value: true }
      ],
      privacy: [
        # Disable Siri suggestions
        { domain: 'com.apple.Siri', key: 'SiriPrefStashedStatusMenuVisible', type: 'bool', value: false },
        # Disable spotlight suggestions
        { domain: 'com.apple.lookup.shared', key: 'LookupSuggestionsDisabled', type: 'bool', value: true }
      ]
    }.freeze

    def initialize(config)
      super('macos_defaults')
      @config = config
      @presets = config[:presets] || []
      @custom = config[:custom] || []
      @restart_apps = config.fetch(:restart_apps, true)
    end

    def install
      return unless Command.macos?

      defaults = collect_defaults
      progress.start(defaults.size)

      apps_to_restart = Set.new

      defaults.each do |setting|
        apply_default(setting)
        apps_to_restart << app_for_domain(setting[:domain])
      end

      if @restart_apps
        restart_affected_apps(apps_to_restart)
      end

      progress.complete
    end

    def uninstall(item)
      # Restore original value if we saved it
      return unless item[:original_value]

      domain = item[:domain]
      key = item[:key]

      if item[:original_value] == :not_set
        Command.run("defaults delete #{domain} #{key}")
      else
        set_default(domain, key, item[:original_type], item[:original_value])
      end
    end

    def installed?(item)
      return false unless item.is_a?(Hash)

      domain = item[:domain]
      key = item[:key]
      expected = item[:value]

      current = get_default(domain, key)
      current.to_s == expected.to_s
    end

    private

    def collect_defaults
      defaults = []

      @presets.each do |preset|
        preset_name = preset.to_sym
        if PRESETS[preset_name]
          defaults.concat(PRESETS[preset_name])
        else
          progress.error("Unknown preset: #{preset}")
        end
      end

      defaults.concat(@custom)
      defaults.uniq { |d| [d[:domain], d[:key]] }
    end

    def apply_default(setting)
      domain = setting[:domain]
      key = setting[:key]
      type = setting[:type]
      value = setting[:value]
      name = "#{domain} #{key}"

      progress.item_started(name)

      # Check if already set
      current = get_default(domain, key)
      if current.to_s == value.to_s
        progress.item_skipped(name)
        return
      end

      # Save original value for rollback
      original_value = current.nil? ? :not_set : current
      original_type = type

      # Apply new value
      result = set_default(domain, key, type, value)
      if result.success?
        record_installation(name,
          type: 'default',
          domain: domain,
          key: key,
          value: value,
          original_value: original_value,
          original_type: original_type)
      else
        progress.error("Failed to set #{name}: #{result.stderr}")
      end
    end

    def get_default(domain, key)
      result = Command.run("defaults read #{domain} #{key} 2>/dev/null")
      return nil unless result.success?
      result.stdout.strip
    end

    def set_default(domain, key, type, value)
      type_flag = case type.to_s
      when 'bool' then '-bool'
      when 'int', 'integer' then '-int'
      when 'float' then '-float'
      when 'string' then '-string'
      when 'array' then '-array'
      when 'dict' then '-dict'
      else '-string'
      end

      # Handle boolean values
      if type.to_s == 'bool'
        value = value ? 'true' : 'false'
      end

      Command.run("defaults write #{domain} #{key} #{type_flag} #{value}")
    end

    def app_for_domain(domain)
      case domain
      when /dock/i then 'Dock'
      when /finder/i then 'Finder'
      when /safari/i then 'Safari'
      when /systemuiserver/i then 'SystemUIServer'
      else nil
      end
    end

    def restart_affected_apps(apps)
      apps.compact.each do |app|
        progress.log("Restarting #{app}...")
        Command.run("killall #{app} 2>/dev/null")
      end
    end
  end

  Registry.register(:macos_defaults, MacosDefaultsInstaller,
    description: 'Configure macOS system preferences',
    order: 6) # After dotfiles, before Homebrew
end

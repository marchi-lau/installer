# frozen_string_literal: true

module Installer
  # Homebrew package installer with uninstall support
  class HomebrewInstaller < Base
    def initialize(config)
      super('homebrew')
      @config = config
      @formulae = config[:formulae] || []
      @casks = config[:casks] || []
      @taps = config[:taps] || []
    end

    def install
      ensure_homebrew_installed
      total = @taps.size + @formulae.size + @casks.size
      progress.start(total)

      install_taps
      install_formulae
      install_casks

      progress.complete
    end

    def uninstall(item)
      case item[:type]
      when 'tap'
        Command.run!("brew untap #{item[:name]}")
      when 'formula'
        Command.run!("brew uninstall #{item[:name]}")
      when 'cask'
        Command.run!("brew uninstall --cask #{item[:name]}")
      end
    end

    def installed?(item)
      case item
      when Hash
        check_installed(item[:name], item[:type])
      when String
        # Default to formula check for string items
        formula_installed?(item) || cask_installed?(item)
      end
    end

    private

    def ensure_homebrew_installed
      return if Command.which('brew')

      progress.log('Homebrew not found. Installing...')
      install_script = '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
      Command.run!(install_script, capture: false)
      record_installation('homebrew-core', type: 'homebrew')
    end

    def install_taps
      @taps.each do |tap|
        progress.item_started(tap)
        next if skip_if_installed({ name: tap, type: 'tap' })

        result = Command.run("brew tap #{tap}")
        if result.success?
          record_installation(tap, type: 'tap')
        else
          progress.error("Failed to tap #{tap}: #{result.stderr}")
        end
      end
    end

    def install_formulae
      @formulae.each do |formula|
        name = formula.is_a?(Hash) ? formula[:name] : formula
        options = formula.is_a?(Hash) ? formula[:options] : ''

        progress.item_started(name)
        next if skip_if_installed({ name: name, type: 'formula' })

        result = Command.run("brew install #{name} #{options}".strip)
        if result.success?
          record_installation(name, type: 'formula', options: options)
        else
          progress.error("Failed to install #{name}: #{result.stderr}")
        end
      end
    end

    def install_casks
      @casks.each do |cask|
        name = cask.is_a?(Hash) ? cask[:name] : cask
        options = cask.is_a?(Hash) ? cask[:options] : ''

        progress.item_started(name)
        next if skip_if_installed({ name: name, type: 'cask' })

        result = Command.run("brew install --cask #{name} #{options}".strip)
        if result.success?
          record_installation(name, type: 'cask', options: options)
        else
          progress.error("Failed to install cask #{name}: #{result.stderr}")
        end
      end
    end

    def check_installed(name, type)
      case type
      when 'tap'
        tap_installed?(name)
      when 'formula'
        formula_installed?(name)
      when 'cask'
        cask_installed?(name)
      else
        false
      end
    end

    def tap_installed?(name)
      result = Command.run("brew tap | grep -q '^#{name}$'")
      result.success?
    end

    def formula_installed?(name)
      result = Command.run("brew list --formula | grep -q '^#{name}$'")
      result.success?
    end

    def cask_installed?(name)
      result = Command.run("brew list --cask | grep -q '^#{name}$'")
      result.success?
    end
  end

  Registry.register(:homebrew, HomebrewInstaller,
    description: 'Install Homebrew formulae and casks',
    order: 10)
end

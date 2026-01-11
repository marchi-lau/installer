# frozen_string_literal: true

require 'yaml'
require 'rake'
require_relative 'lib/installer'

CONFIG_FILE = ENV['CONFIG_FILE'] || 'config.yml'

def load_config
  unless File.exist?(CONFIG_FILE)
    puts "Config file not found: #{CONFIG_FILE}"
    puts "Run 'rake config:generate' to create a sample config"
    exit 1
  end

  YAML.load_file(CONFIG_FILE, symbolize_names: true)
end

namespace :install do
  desc 'Run all enabled installers'
  task :all do
    config = load_config
    success = Installer.run_all(config)
    exit 1 unless success
  end

  desc 'Install only Homebrew packages (formulae, casks, taps)'
  task :homebrew do
    config = load_config
    installer = Installer::HomebrewInstaller.new(config[:homebrew])
    installer.install
  end

  desc 'Install only App Store apps via mas'
  task :appstore do
    config = load_config
    installer = Installer::AppStoreInstaller.new(config[:appstore])
    installer.install
  end

  desc 'Install only development tools (VS Code extensions, npm, pip)'
  task :codex do
    config = load_config
    installer = Installer::CodexInstaller.new(config[:codex])
    installer.install
  end

  desc 'Install rbenv and Ruby versions'
  task :rbenv do
    config = load_config
    installer = Installer::RbenvInstaller.new(config[:rbenv])
    installer.install
  end

  desc 'Dry run - show what would be installed without making changes'
  task :dry_run do
    config = load_config
    puts Installer::Orchestrator.new(config).send(:banner, 'Dry Run - Installation Plan')

    Installer::Registry.all.each do |name, entry|
      next unless config.dig(name, :enabled)

      puts "\n#{name.to_s.upcase}:"
      section_config = config[name]

      case name
      when :homebrew
        puts "  Taps: #{section_config[:taps]&.join(', ') || 'none'}"
        puts "  Formulae: #{section_config[:formulae]&.size || 0} packages"
        puts "  Casks: #{section_config[:casks]&.size || 0} applications"
      when :codex
        puts "  VS Code Extensions: #{section_config[:vscode_extensions]&.size || 0}"
        puts "  NPM Globals: #{section_config[:npm_globals]&.size || 0}"
        puts "  Pip Packages: #{section_config[:pip_packages]&.size || 0}"
        puts "  Custom Scripts: #{section_config[:custom_scripts]&.size || 0}"
      when :appstore
        puts "  Apps: #{section_config[:apps]&.size || 0} applications"
      when :rbenv
        puts "  Ruby Versions: #{section_config[:ruby_versions]&.join(', ') || 'none'}"
        puts "  Default: #{section_config[:default_version] || 'none'}"
        puts "  Global Gems: #{section_config[:global_gems]&.size || 0}"
        puts "  Plugins: #{section_config[:plugins]&.size || 0}"
      end
    end
    puts
  end
end

namespace :rollback do
  desc 'Rollback all installations'
  task :all do
    config = load_config
    Installer.rollback_all(config)
  end

  desc 'Rollback only Homebrew installations'
  task :homebrew do
    config = load_config
    installer = Installer::HomebrewInstaller.new(config[:homebrew])
    installer.rollback
  end

  desc 'Rollback only App Store installations'
  task :appstore do
    config = load_config
    installer = Installer::AppStoreInstaller.new(config[:appstore])
    installer.rollback
  end

  desc 'Rollback only development tools'
  task :codex do
    config = load_config
    installer = Installer::CodexInstaller.new(config[:codex])
    installer.rollback
  end

  desc 'Rollback rbenv and Ruby versions'
  task :rbenv do
    config = load_config
    installer = Installer::RbenvInstaller.new(config[:rbenv])
    installer.rollback
  end
end

namespace :status do
  desc 'Show installation status for all components'
  task :all do
    state_dir = Installer::Base::STATE_DIR
    puts "\n" + '═' * 50
    puts "  Installation Status"
    puts '═' * 50

    if Dir.exist?(state_dir)
      Dir.glob(File.join(state_dir, '*_state.json')).each do |file|
        data = JSON.parse(File.read(file), symbolize_names: true)
        name = data[:name]
        items = data[:installed_items] || []
        last_updated = data[:last_updated]

        puts "\n#{name.upcase}:"
        puts "  Last updated: #{last_updated}"
        puts "  Installed items: #{items.size}"
        items.last(5).each do |item|
          puts "    - #{item[:name]} (#{item[:type]})"
        end
        puts "    ... and #{items.size - 5} more" if items.size > 5
      end
    else
      puts "\nNo installation state found."
      puts "Run 'rake install:all' to begin installation."
    end
    puts
  end

  desc 'Check system prerequisites'
  task :check do
    puts "\n" + '═' * 50
    puts "  System Prerequisites Check"
    puts '═' * 50

    checks = {
      'macOS' => -> { Installer::Command.macos? },
      'Homebrew' => -> { Installer::Command.which('brew') },
      'mas CLI' => -> { Installer::Command.which('mas') },
      'rbenv' => -> { Installer::Command.which('rbenv') },
      'Ruby' => -> { Installer::Command.which('ruby') },
      'Node.js' => -> { Installer::Command.which('node') },
      'npm' => -> { Installer::Command.which('npm') },
      'Python 3' => -> { Installer::Command.which('python3') },
      'pip3' => -> { Installer::Command.which('pip3') },
      'VS Code CLI' => -> { Installer::Command.which('code') }
    }

    checks.each do |name, check|
      status = check.call ? "\e[32m✓\e[0m" : "\e[31m✗\e[0m"
      puts "  #{status} #{name}"
    end

    if Installer::Command.macos?
      puts "\n  macOS Version: #{Installer::Command.macos_version}"
    end
    puts
  end
end

namespace :config do
  desc 'Generate a sample configuration file'
  task :generate do
    sample_config = <<~YAML
      # macOS Installer Configuration
      # Customize this file with your preferred apps and tools

      # Global settings
      halt_on_error: false

      # Homebrew packages
      homebrew:
        enabled: true
        taps:
          - homebrew/cask-fonts
          - homebrew/cask-versions

        formulae:
          - git
          - wget
          - curl
          - jq
          - tree
          - htop
          - neovim
          - ripgrep
          - fzf
          - tmux
          - gh  # GitHub CLI

        casks:
          - visual-studio-code
          - iterm2
          - docker
          - rectangle
          - alfred
          - 1password
          - slack
          - notion
          - figma
          - postman

      # Ruby version manager
      rbenv:
        enabled: true
        ruby_versions:
          - 3.3.0
          - 3.2.2
        default_version: 3.3.0
        plugins:
          - name: rbenv-gemset
            repo: jf/rbenv-gemset
        global_gems:
          - bundler
          - rake
          - solargraph
          - rubocop
          - pry
          - nokogiri
          - sinatra

      # Development tools
      codex:
        enabled: true
        vscode_extensions:
          - ms-python.python
          - ms-vscode.vscode-typescript-next
          - esbenp.prettier-vscode
          - dbaeumer.vscode-eslint
          - eamodio.gitlens
          - github.copilot
          - bradlc.vscode-tailwindcss

        npm_globals:
          - typescript
          - eslint
          - prettier
          - nodemon
          - yarn
          - pnpm

        pip_packages:
          - black
          - flake8
          - mypy
          - poetry

        custom_scripts:
          - name: Oh My Zsh
            install: sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
            rollback: rm -rf ~/.oh-my-zsh
            check: test -d ~/.oh-my-zsh

      # Mac App Store apps (requires App Store sign-in)
      appstore:
        enabled: true
        require_signin: true
        apps:
          - id: 497799835
            name: Xcode
          - id: 1475387142
            name: Tailscale
          - id: 937984704
            name: Amphetamine
          - id: 1176895641
            name: Spark
    YAML

    if File.exist?(CONFIG_FILE) && !ENV['FORCE']
      puts "Config file already exists: #{CONFIG_FILE}"
      puts "Set FORCE=1 to overwrite"
      exit 1
    end

    File.write(CONFIG_FILE, sample_config)
    puts "Generated sample config: #{CONFIG_FILE}"
    puts "Edit this file to customize your installation."
  end

  desc 'Validate configuration file'
  task :validate do
    config = load_config
    errors = []

    # Validate homebrew section
    if config[:homebrew]
      %i[formulae casks taps].each do |key|
        if config[:homebrew][key] && !config[:homebrew][key].is_a?(Array)
          errors << "homebrew.#{key} must be an array"
        end
      end
    end

    # Validate appstore section
    if config[:appstore]&.dig(:apps)
      config[:appstore][:apps].each_with_index do |app, i|
        errors << "appstore.apps[#{i}] must have an 'id'" unless app[:id]
      end
    end

    if errors.empty?
      puts "\e[32m✓ Configuration is valid\e[0m"
    else
      puts "\e[31m✗ Configuration errors:\e[0m"
      errors.each { |e| puts "  - #{e}" }
      exit 1
    end
  end
end

# Default task
desc 'Show available tasks'
task :default do
  puts <<~HELP

    \e[1mmacOS Installer - Rake Tasks\e[0m
    ═══════════════════════════════════════════════════

    \e[36mInstallation:\e[0m
      rake install:all        Run all enabled installers
      rake install:homebrew   Install only Homebrew packages
      rake install:rbenv      Install rbenv and Ruby versions
      rake install:codex      Install only dev tools
      rake install:appstore   Install only App Store apps
      rake install:dry_run    Preview what would be installed

    \e[36mRollback:\e[0m
      rake rollback:all       Rollback all installations
      rake rollback:homebrew  Rollback Homebrew only
      rake rollback:rbenv     Rollback rbenv only
      rake rollback:codex     Rollback dev tools only
      rake rollback:appstore  Rollback App Store only

    \e[36mStatus:\e[0m
      rake status:all         Show installation status
      rake status:check       Check system prerequisites

    \e[36mConfiguration:\e[0m
      rake config:generate    Generate sample config.yml
      rake config:validate    Validate configuration file

    \e[33mUsage:\e[0m
      1. Run 'rake config:generate' to create config.yml
      2. Edit config.yml with your preferred apps
      3. Run 'rake status:check' to verify prerequisites
      4. Run 'rake install:all' to start installation

    \e[33mEnvironment Variables:\e[0m
      CONFIG_FILE=path/to/config.yml   Use custom config file

  HELP
end

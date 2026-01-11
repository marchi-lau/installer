# macOS Installer

A modular, uninstall-capable macOS setup automation tool built with Rake.

## Features

- **Modular Installers** - Dotfiles, macOS defaults, Homebrew, rbenv, pyenv, fnm, VS Code, App Store
- **Dotfiles Manager** - Clone repo, symlink configs, backup existing files
- **macOS Defaults** - System preferences via presets (developer, dock, trackpad, etc.)
- **Notifications** - macOS notifications when install completes
- **Progress Tracking** - Colored output with progress bars
- **Uninstall Support** - Undo installations with state persistence
- **Scan & Migrate** - Scan old Mac and generate config for new Mac
- **Idempotent** - Skips already-installed items
- **Lockfile** - Prevents concurrent runs

## Quick Start

```bash
# Clone the repo
git clone https://github.com/marchi-lau/installer.git
cd installer

# Install Ruby dependencies
bundle install

# Check prerequisites
rake status:check

# Preview installation
rake install:dry_run

# Run full installation
rake install:all
```

## Available Installers

| Order | Installer | Description | Config Key |
|-------|-----------|-------------|------------|
| 1 | **Dotfiles** | Clone repo, symlink configs | `dotfiles` |
| 2 | **macOS Defaults** | System preferences | `macos_defaults` |
| 3 | **Homebrew** | Formulae, casks, taps | `homebrew` |
| 4 | **rbenv** | Ruby versions + gems | `rbenv` |
| 5 | **pyenv** | Python versions + packages | `pyenv` |
| 6 | **fnm** | Node.js versions + npm packages | `fnm` |
| 7 | **Codex** | VS Code extensions, npm, pip | `codex` |
| 8 | **App Store** | Mac App Store via mas | `appstore` |

## Rake Tasks

### Installation

```bash
rake install:all            # Run all enabled installers
rake install:dotfiles       # Clone and symlink dotfiles
rake install:macos_defaults # Apply macOS system preferences
rake install:homebrew       # Homebrew packages only
rake install:rbenv          # Ruby versions only
rake install:pyenv          # Python versions only
rake install:fnm            # Node.js versions only
rake install:codex          # Dev tools only
rake install:appstore       # App Store apps only
rake install:dry_run        # Preview what would be installed
```

### Uninstall

```bash
rake uninstall:all            # Undo all installations
rake uninstall:dotfiles       # Remove symlinks, restore backups
rake uninstall:macos_defaults # Reset to original values
rake uninstall:homebrew       # Undo Homebrew only
rake uninstall:rbenv          # Undo rbenv only
rake uninstall:pyenv          # Undo pyenv only
rake uninstall:fnm            # Undo fnm only
rake uninstall:codex          # Undo dev tools only
rake uninstall:appstore       # Undo App Store only
```

### Status

```bash
rake status:check       # Check system prerequisites
rake status:all         # View installation history
rake                    # Show all available tasks
```

### Configuration

```bash
rake config:generate    # Generate sample config.yml
rake config:validate    # Validate configuration
```

### Scan (Migrate from Old Mac)

```bash
rake scan:show          # Scan and display installed apps
rake scan:generate      # Generate config from installed apps
rake scan:homebrew      # Scan only Homebrew packages
rake scan:versions      # Scan only rbenv/pyenv/fnm
rake scan:appstore      # Scan only App Store apps
```

## Migrate from Old Mac

Transfer your setup from an old Mac to a new one:

```bash
# On OLD Mac: scan and generate config
cd installer
rake scan:generate
# Creates scanned_config.yml

# Copy to NEW Mac (via AirDrop, USB, cloud, etc.)
scp scanned_config.yml newmac:~/installer/

# On NEW Mac: install everything
cd installer
CONFIG_FILE=scanned_config.yml rake install:all
```

The scanner detects:
- Homebrew formulae, casks, and taps
- Ruby versions and gems (rbenv)
- Python versions and packages (pyenv)
- Node.js versions and npm packages (fnm)
- VS Code extensions
- Mac App Store apps

## Configuration

Edit `config.yml` to customize your installation:

```yaml
# Global settings
notifications: true      # macOS notifications when done
halt_on_error: false     # Stop on first error

# Dotfiles - clone and symlink
dotfiles:
  enabled: true
  repo: https://github.com/YOUR_USER/dotfiles.git
  target_dir: ~/dotfiles
  symlinks:
    - source: zshrc
      target: ~/.zshrc
    - source: gitconfig
      target: ~/.gitconfig

# macOS system preferences
macos_defaults:
  enabled: true
  presets:
    - developer  # Show hidden files, fast key repeat
    - dock       # Auto-hide, no recents
    - trackpad   # Tap to click
  custom:
    - domain: com.apple.dock
      key: tilesize
      type: int
      value: 36

# Homebrew packages
homebrew:
  enabled: true
  taps:
    - homebrew/cask-fonts
  formulae:
    - git
    - gh
    - neovim
  casks:
    - visual-studio-code
    - docker

# Ruby versions
rbenv:
  enabled: true
  ruby_versions:
    - 3.3.0
    - 3.2.2
  default_version: 3.3.0
  global_gems:
    - bundler
    - rails

# Python versions
pyenv:
  enabled: true
  python_versions:
    - 3.12.0
    - 3.11.0
  default_version: 3.12.0
  global_packages:
    - poetry
    - black

# Node.js versions
fnm:
  enabled: true
  node_versions:
    - 22
    - 20
    - lts-iron
  default_version: 22
  global_packages:
    - typescript
    - pnpm
```

## Environment Variables

```bash
CONFIG_FILE=~/my-config.yml rake install:all
```

## State & Uninstall

Installation state is persisted to `~/.macos_installer/`:

```
~/.macos_installer/
├── .installer.lock      # Prevents concurrent runs
├── homebrew_state.json  # Installed Homebrew items
├── rbenv_state.json     # Installed Ruby versions
├── pyenv_state.json     # Installed Python versions
├── fnm_state.json       # Installed Node versions
├── codex_state.json     # Installed dev tools
└── appstore_state.json  # Installed App Store apps
```

Uninstall uses these state files to undo installations in reverse order.

## Adding Custom Installers

Create a new file in `lib/installer/installers/`:

```ruby
# lib/installer/installers/my_tool.rb
module Installer
  class MyToolInstaller < Base
    def initialize(config)
      super('my_tool')
      @config = config
    end

    def install
      # Implementation
    end

    def uninstall(item)
      # Uninstall implementation
    end

    def installed?(item)
      # Check if already installed
    end
  end

  Registry.register(:my_tool, MyToolInstaller,
    description: 'Install my tool',
    order: 50)
end
```

## Requirements

- macOS (tested on Ventura, Sonoma)
- Ruby 3.0+
- Bundler

## License

MIT

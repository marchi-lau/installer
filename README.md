# macOS Installer

A modular, uninstall-capable macOS setup automation tool built with Rake.

## Features

- **Modular Installers** - Homebrew, rbenv, pyenv, fnm, VS Code, App Store
- **Progress Tracking** - Colored output with progress bars
- **Uninstall Support** - Undo installations with state persistence
- **Scan & Migrate** - Scan old Mac and generate config for new Mac
- **Idempotent** - Skips already-installed items
- **Lockfile** - Prevents concurrent runs
- **Extensible** - Plugin registry for custom installers

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

| Installer | Description | Config Key |
|-----------|-------------|------------|
| **Homebrew** | Formulae, casks, taps | `homebrew` |
| **rbenv** | Ruby versions + gems | `rbenv` |
| **pyenv** | Python versions + packages | `pyenv` |
| **fnm** | Node.js versions + npm packages | `fnm` |
| **Codex** | VS Code extensions, npm, pip | `codex` |
| **App Store** | Mac App Store via mas | `appstore` |

## Rake Tasks

### Installation

```bash
rake install:all        # Run all enabled installers
rake install:homebrew   # Homebrew packages only
rake install:rbenv      # Ruby versions only
rake install:pyenv      # Python versions only
rake install:fnm        # Node.js versions only
rake install:codex      # Dev tools only
rake install:appstore   # App Store apps only
rake install:dry_run    # Preview what would be installed
```

### Uninstall

```bash
rake uninstall:all       # Undo all installations
rake uninstall:homebrew  # Undo Homebrew only
rake uninstall:rbenv     # Undo rbenv only
rake uninstall:pyenv     # Undo pyenv only
rake uninstall:fnm       # Undo fnm only
rake uninstall:codex     # Undo dev tools only
rake uninstall:appstore  # Undo App Store only
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
# Disable a section
appstore:
  enabled: false

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

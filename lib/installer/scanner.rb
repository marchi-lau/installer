# frozen_string_literal: true

require 'yaml'
require 'json'

module Installer
  # Scans existing macOS installation and generates config
  class Scanner
    SCAN_COMPONENTS = %i[homebrew rbenv pyenv fnm codex appstore].freeze

    def initialize(options = {})
      @options = options
      @progress = Progress.new('scanner')
      @results = {}
    end

    def scan(components = SCAN_COMPONENTS)
      puts banner('Scanning System')
      puts "Started at: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
      puts

      components.each do |component|
        scan_component(component)
      end

      print_summary
      @results
    end

    def generate_config(output_path = 'config.yml')
      scan if @results.empty?

      config = build_config
      yaml = YAML.dump(deep_stringify_keys(config))

      # Clean up YAML formatting
      yaml = yaml.gsub(/^---\n/, '')
      yaml = "# macOS Installer Configuration\n# Generated from system scan on #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}\n\n" + yaml

      File.write(output_path, yaml)
      puts "\n\e[32m✓ Config written to #{output_path}\e[0m"
      output_path
    end

    private

    def scan_component(component)
      print "\e[36m▶ Scanning #{component}...\e[0m "

      result = case component
      when :homebrew then scan_homebrew
      when :rbenv then scan_rbenv
      when :pyenv then scan_pyenv
      when :fnm then scan_fnm
      when :codex then scan_codex
      when :appstore then scan_appstore
      end

      @results[component] = result
      puts "\e[32m✓\e[0m"
    rescue StandardError => e
      puts "\e[31m✗ #{e.message}\e[0m"
      @results[component] = nil
    end

    # Homebrew scanning
    def scan_homebrew
      return nil unless Command.which('brew')

      {
        taps: scan_brew_taps,
        formulae: scan_brew_formulae,
        casks: scan_brew_casks
      }
    end

    def scan_brew_taps
      result = Command.run('brew tap')
      return [] unless result.success?

      result.stdout.split("\n").reject do |tap|
        # Skip default taps
        %w[homebrew/core homebrew/cask].include?(tap)
      end
    end

    def scan_brew_formulae
      result = Command.run('brew leaves')
      return [] unless result.success?
      result.stdout.split("\n")
    end

    def scan_brew_casks
      result = Command.run('brew list --cask')
      return [] unless result.success?
      result.stdout.split("\n")
    end

    # rbenv scanning
    def scan_rbenv
      return nil unless Command.which('rbenv')

      versions = scan_rbenv_versions
      return nil if versions.empty?

      {
        ruby_versions: versions,
        default_version: scan_rbenv_default,
        global_gems: scan_global_gems(versions.first)
      }
    end

    def scan_rbenv_versions
      result = Command.run('rbenv versions --bare')
      return [] unless result.success?
      result.stdout.split("\n").map(&:strip)
    end

    def scan_rbenv_default
      result = Command.run('rbenv global')
      return nil unless result.success?
      result.stdout.strip
    end

    def scan_global_gems(ruby_version)
      return [] unless ruby_version

      result = Command.run("RBENV_VERSION=#{ruby_version} rbenv exec gem list --no-versions")
      return [] unless result.success?

      gems = result.stdout.split("\n")
      # Filter out default gems
      default_gems = %w[bigdecimal bundler cgi date delegate did_you_mean drb english erb etc
                        fcntl fiddle fileutils find forwardable getoptlong io-console io-nonblock
                        io-wait ipaddr irb json logger mutex_m net-http net-protocol observer open-uri
                        open3 openssl optparse ostruct pathname power_assert pp prettyprint prism
                        pstore psych racc rdoc readline reline resolv resolv-replace rexml rinda
                        ruby2_keywords securerandom set shellwords singleton stringio strscan
                        syntax_suggest syslog tempfile time timeout tmpdir tsort typeprof un uri
                        weakref win32ole yaml zlib]

      gems.reject { |g| default_gems.include?(g) }
    end

    # pyenv scanning
    def scan_pyenv
      return nil unless Command.which('pyenv')

      versions = scan_pyenv_versions
      return nil if versions.empty?

      {
        python_versions: versions,
        default_version: scan_pyenv_default,
        global_packages: scan_pip_packages(versions.first)
      }
    end

    def scan_pyenv_versions
      result = Command.run('pyenv versions --bare')
      return [] unless result.success?
      result.stdout.split("\n").map(&:strip).reject { |v| v.include?('/') }
    end

    def scan_pyenv_default
      result = Command.run('pyenv global')
      return nil unless result.success?
      version = result.stdout.strip
      version == 'system' ? nil : version
    end

    def scan_pip_packages(python_version)
      return [] unless python_version

      result = Command.run("PYENV_VERSION=#{python_version} pyenv exec pip list --format=json 2>/dev/null")
      return [] unless result.success?

      packages = JSON.parse(result.stdout)
      # Filter out standard library packages
      skip_packages = %w[pip setuptools wheel]

      packages.map { |p| p['name'] }.reject { |p| skip_packages.include?(p.downcase) }
    rescue JSON::ParserError
      []
    end

    # fnm scanning
    def scan_fnm
      return nil unless Command.which('fnm')

      versions = scan_fnm_versions
      return nil if versions.empty?

      {
        node_versions: versions,
        default_version: scan_fnm_default,
        global_packages: scan_npm_globals
      }
    end

    def scan_fnm_versions
      result = Command.run('fnm list')
      return [] unless result.success?

      result.stdout.split("\n").map do |line|
        # Parse fnm list output (e.g., "* v20.10.0 default")
        match = line.match(/v(\d+\.\d+\.\d+)/)
        match ? match[1] : nil
      end.compact.uniq
    end

    def scan_fnm_default
      result = Command.run('fnm current')
      return nil unless result.success?
      version = result.stdout.strip.sub(/^v/, '')
      version == 'none' ? nil : version
    end

    def scan_npm_globals
      result = Command.run('npm list -g --depth=0 --json 2>/dev/null')
      return [] unless result.success?

      data = JSON.parse(result.stdout)
      deps = data['dependencies'] || {}

      # Filter out npm itself
      deps.keys.reject { |p| p == 'npm' }
    rescue JSON::ParserError
      []
    end

    # Codex (VS Code, etc.) scanning
    def scan_codex
      {
        vscode_extensions: scan_vscode_extensions,
        npm_globals: [], # Already captured in fnm
        pip_packages: [] # Already captured in pyenv
      }
    end

    def scan_vscode_extensions
      return [] unless Command.which('code')

      result = Command.run('code --list-extensions')
      return [] unless result.success?
      result.stdout.split("\n")
    end

    # App Store scanning
    def scan_appstore
      return nil unless Command.which('mas')

      {
        apps: scan_mas_apps
      }
    end

    def scan_mas_apps
      result = Command.run('mas list')
      return [] unless result.success?

      result.stdout.split("\n").map do |line|
        # Parse mas list output (e.g., "497799835  Xcode (15.0)")
        match = line.match(/^(\d+)\s+(.+?)\s+\(/)
        next unless match

        { id: match[1].to_i, name: match[2].strip }
      end.compact
    end

    def build_config
      config = { halt_on_error: false }

      if @results[:homebrew]
        config[:homebrew] = {
          enabled: true,
          taps: @results[:homebrew][:taps],
          formulae: @results[:homebrew][:formulae],
          casks: @results[:homebrew][:casks]
        }
      end

      if @results[:rbenv]
        config[:rbenv] = {
          enabled: true,
          ruby_versions: @results[:rbenv][:ruby_versions],
          default_version: @results[:rbenv][:default_version],
          global_gems: @results[:rbenv][:global_gems]
        }
      end

      if @results[:pyenv]
        config[:pyenv] = {
          enabled: true,
          python_versions: @results[:pyenv][:python_versions],
          default_version: @results[:pyenv][:default_version],
          global_packages: @results[:pyenv][:global_packages]
        }
      end

      if @results[:fnm]
        config[:fnm] = {
          enabled: true,
          node_versions: @results[:fnm][:node_versions],
          default_version: @results[:fnm][:default_version],
          global_packages: @results[:fnm][:global_packages]
        }
      end

      if @results[:codex] && @results[:codex][:vscode_extensions]&.any?
        config[:codex] = {
          enabled: true,
          vscode_extensions: @results[:codex][:vscode_extensions],
          npm_globals: [],
          pip_packages: [],
          custom_scripts: []
        }
      end

      if @results[:appstore] && @results[:appstore][:apps]&.any?
        config[:appstore] = {
          enabled: true,
          require_signin: true,
          apps: @results[:appstore][:apps]
        }
      end

      config
    end

    def print_summary
      puts
      puts banner('Scan Summary')

      @results.each do |component, data|
        next unless data

        print "\e[36m#{component}:\e[0m "
        case component
        when :homebrew
          puts "#{data[:formulae]&.size || 0} formulae, #{data[:casks]&.size || 0} casks, #{data[:taps]&.size || 0} taps"
        when :rbenv
          puts "#{data[:ruby_versions]&.size || 0} versions, #{data[:global_gems]&.size || 0} gems"
        when :pyenv
          puts "#{data[:python_versions]&.size || 0} versions, #{data[:global_packages]&.size || 0} packages"
        when :fnm
          puts "#{data[:node_versions]&.size || 0} versions, #{data[:global_packages]&.size || 0} packages"
        when :codex
          puts "#{data[:vscode_extensions]&.size || 0} VS Code extensions"
        when :appstore
          puts "#{data[:apps]&.size || 0} apps"
        end
      end
    end

    def banner(title)
      line = '═' * 50
      "\n#{line}\n  #{title}\n#{line}"
    end

    def deep_stringify_keys(hash)
      hash.transform_keys(&:to_s).transform_values do |value|
        case value
        when Hash then deep_stringify_keys(value)
        when Array then value.map { |v| v.is_a?(Hash) ? deep_stringify_keys(v) : v }
        else value
        end
      end
    end
  end
end

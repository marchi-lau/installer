# frozen_string_literal: true

module Installer
  # Git configuration and SSH key setup
  class GitSshInstaller < Base
    SSH_DIR = File.expand_path('~/.ssh')
    DEFAULT_KEY_TYPE = 'ed25519'

    def initialize(config)
      super('git_ssh')
      @config = config
      @git_config = config[:git] || {}
      @ssh_config = config[:ssh] || {}
    end

    def install
      items = []
      items << :git_config if @git_config.any?
      items << :ssh_key if @ssh_config[:generate_key]
      items << :ssh_agent if @ssh_config[:add_to_agent]
      items << :ssh_config_file if @ssh_config[:configure_hosts]

      progress.start(items.size)

      configure_git if @git_config.any?
      generate_ssh_key if @ssh_config[:generate_key]
      add_to_ssh_agent if @ssh_config[:add_to_agent]
      configure_ssh_hosts if @ssh_config[:configure_hosts]

      show_public_key if @ssh_config[:generate_key]

      progress.complete
    end

    def uninstall(item)
      case item[:type]
      when 'git_config'
        unset_git_config(item[:key])
      when 'ssh_key'
        remove_ssh_key(item[:key_path])
      end
    end

    def installed?(item)
      case item
      when Hash
        case item[:type]
        when 'git_config'
          get_git_config(item[:key]) == item[:value]
        when 'ssh_key'
          File.exist?(item[:key_path])
        end
      else
        false
      end
    end

    private

    # Git configuration
    def configure_git
      progress.item_started('Git config')

      git_settings = {
        'user.name' => @git_config[:name],
        'user.email' => @git_config[:email],
        'init.defaultBranch' => @git_config[:default_branch] || 'main',
        'core.editor' => @git_config[:editor],
        'pull.rebase' => @git_config[:pull_rebase],
        'push.autoSetupRemote' => @git_config[:auto_setup_remote],
        'core.autocrlf' => @git_config[:autocrlf]
      }.compact

      # Add aliases
      (@git_config[:aliases] || {}).each do |name, command|
        git_settings["alias.#{name}"] = command
      end

      git_settings.each do |key, value|
        current = get_git_config(key)
        next if current == value.to_s

        set_git_config(key, value)
        record_installation("git #{key}", type: 'git_config', key: key, value: value.to_s)
      end

      progress.item_completed('Git config')
    end

    def get_git_config(key)
      result = Command.run("git config --global --get #{key}")
      result.success? ? result.stdout.strip : nil
    end

    def set_git_config(key, value)
      # Handle boolean values
      value = value.to_s
      Command.run!("git config --global #{key} '#{value}'")
    end

    def unset_git_config(key)
      Command.run("git config --global --unset #{key}")
    end

    # SSH key generation
    def generate_ssh_key
      progress.item_started('SSH key')

      key_type = @ssh_config[:key_type] || DEFAULT_KEY_TYPE
      key_name = @ssh_config[:key_name] || "id_#{key_type}"
      key_path = File.join(SSH_DIR, key_name)
      email = @ssh_config[:email] || @git_config[:email]
      passphrase = @ssh_config[:passphrase] || ''

      if File.exist?(key_path)
        progress.item_skipped('SSH key (already exists)')
        return
      end

      # Ensure .ssh directory exists with correct permissions
      FileUtils.mkdir_p(SSH_DIR)
      FileUtils.chmod(0700, SSH_DIR)

      # Generate key
      cmd = "ssh-keygen -t #{key_type} -C '#{email}' -f '#{key_path}' -N '#{passphrase}'"
      result = Command.run(cmd)

      if result.success?
        FileUtils.chmod(0600, key_path)
        FileUtils.chmod(0644, "#{key_path}.pub")
        record_installation('SSH key', type: 'ssh_key', key_path: key_path, key_type: key_type)
      else
        progress.error("Failed to generate SSH key: #{result.stderr}")
      end
    end

    def remove_ssh_key(key_path)
      FileUtils.rm_f(key_path)
      FileUtils.rm_f("#{key_path}.pub")
    end

    # SSH agent
    def add_to_ssh_agent
      progress.item_started('SSH agent')

      key_type = @ssh_config[:key_type] || DEFAULT_KEY_TYPE
      key_name = @ssh_config[:key_name] || "id_#{key_type}"
      key_path = File.join(SSH_DIR, key_name)

      unless File.exist?(key_path)
        progress.error('SSH key not found')
        return
      end

      # Start ssh-agent if not running
      Command.run('eval "$(ssh-agent -s)"') unless ENV['SSH_AUTH_SOCK']

      # Add to keychain on macOS
      if Command.macos?
        configure_ssh_agent_macos(key_path)
      else
        Command.run("ssh-add #{key_path}")
      end

      progress.item_completed('SSH agent')
    end

    def configure_ssh_agent_macos(key_path)
      # Create/update SSH config for macOS keychain integration
      ssh_config_path = File.join(SSH_DIR, 'config')

      agent_config = <<~CONFIG
        Host *
          AddKeysToAgent yes
          UseKeychain yes
          IdentityFile #{key_path}
      CONFIG

      if File.exist?(ssh_config_path)
        existing = File.read(ssh_config_path)
        unless existing.include?('UseKeychain')
          File.open(ssh_config_path, 'a') { |f| f.write("\n#{agent_config}") }
        end
      else
        File.write(ssh_config_path, agent_config)
        FileUtils.chmod(0600, ssh_config_path)
      end

      # Add to keychain
      Command.run("ssh-add --apple-use-keychain #{key_path}")
    end

    # SSH host configuration
    def configure_ssh_hosts
      progress.item_started('SSH hosts config')

      hosts = @ssh_config[:hosts] || []
      return if hosts.empty?

      ssh_config_path = File.join(SSH_DIR, 'config')
      existing_config = File.exist?(ssh_config_path) ? File.read(ssh_config_path) : ''

      hosts.each do |host|
        host_block = build_host_block(host)
        next if existing_config.include?("Host #{host[:name]}")

        File.open(ssh_config_path, 'a') { |f| f.write("\n#{host_block}") }
      end

      FileUtils.chmod(0600, ssh_config_path)
      progress.item_completed('SSH hosts config')
    end

    def build_host_block(host)
      lines = ["Host #{host[:name]}"]
      lines << "  HostName #{host[:hostname]}" if host[:hostname]
      lines << "  User #{host[:user]}" if host[:user]
      lines << "  IdentityFile #{host[:identity_file]}" if host[:identity_file]
      lines << "  Port #{host[:port]}" if host[:port]
      lines.join("\n") + "\n"
    end

    def show_public_key
      key_type = @ssh_config[:key_type] || DEFAULT_KEY_TYPE
      key_name = @ssh_config[:key_name] || "id_#{key_type}"
      pub_key_path = File.join(SSH_DIR, "#{key_name}.pub")

      return unless File.exist?(pub_key_path)

      pub_key = File.read(pub_key_path).strip

      puts
      puts "\e[36m═══════════════════════════════════════════════════\e[0m"
      puts "\e[1m  Your SSH Public Key\e[0m"
      puts "\e[36m═══════════════════════════════════════════════════\e[0m"
      puts
      puts pub_key
      puts

      # Copy to clipboard on macOS
      if Command.macos?
        Command.run("echo '#{pub_key}' | pbcopy")
        puts "\e[32m✓ Copied to clipboard!\e[0m"
        puts
        puts "Add this key to:"
        puts "  • GitHub: https://github.com/settings/ssh/new"
        puts "  • GitLab: https://gitlab.com/-/profile/keys"
        puts
      end
    end
  end

  Registry.register(:git_ssh, GitSshInstaller,
    description: 'Configure Git and SSH keys',
    order: 4) # After dotfiles, before macos_defaults
end

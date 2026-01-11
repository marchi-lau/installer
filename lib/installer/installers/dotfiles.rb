# frozen_string_literal: true

module Installer
  # Dotfiles manager - clone repo and symlink config files
  class DotfilesInstaller < Base
    def initialize(config)
      super('dotfiles')
      @config = config
      @repo = config[:repo]
      @target_dir = File.expand_path(config[:target_dir] || '~/dotfiles')
      @symlinks = config[:symlinks] || []
      @backup_dir = File.expand_path(config[:backup_dir] || '~/.dotfiles_backup')
    end

    def install
      return unless @repo

      total = 1 + @symlinks.size
      progress.start(total)

      clone_repo
      create_symlinks

      progress.complete
    end

    def uninstall(item)
      case item[:type]
      when 'repo'
        remove_repo
      when 'symlink'
        remove_symlink(item)
      end
    end

    def installed?(item)
      case item
      when Hash
        case item[:type]
        when 'repo'
          File.directory?(@target_dir) && File.directory?(File.join(@target_dir, '.git'))
        when 'symlink'
          target = File.expand_path(item[:target])
          File.symlink?(target)
        end
      else
        false
      end
    end

    private

    def clone_repo
      progress.item_started('dotfiles repo')

      if installed?({ type: 'repo' })
        # Pull latest if already cloned
        progress.log('Repo exists, pulling latest...')
        result = Command.run("git -C #{@target_dir} pull")
        if result.success?
          progress.item_completed('dotfiles repo (updated)')
        else
          progress.error("Failed to update repo: #{result.stderr}")
        end
        return
      end

      result = Command.run("git clone #{@repo} #{@target_dir}")
      if result.success?
        record_installation('dotfiles repo', type: 'repo', repo: @repo, target_dir: @target_dir)
      else
        raise CommandError, "Failed to clone dotfiles: #{result.stderr}"
      end
    end

    def create_symlinks
      @symlinks.each do |link|
        source = File.expand_path(link[:source], @target_dir)
        target = File.expand_path(link[:target])
        name = link[:name] || File.basename(target)

        progress.item_started(name)

        unless File.exist?(source)
          progress.error("Source not found: #{source}")
          next
        end

        if File.symlink?(target)
          current_source = File.readlink(target)
          if current_source == source
            progress.item_skipped(name)
            next
          else
            # Remove old symlink
            FileUtils.rm(target)
          end
        elsif File.exist?(target)
          # Backup existing file
          backup_file(target)
        end

        # Create parent directory if needed
        FileUtils.mkdir_p(File.dirname(target))

        # Create symlink
        FileUtils.ln_s(source, target)
        record_installation(name, type: 'symlink', source: source, target: target)
      end
    end

    def backup_file(path)
      FileUtils.mkdir_p(@backup_dir)
      backup_name = "#{File.basename(path)}.#{Time.now.strftime('%Y%m%d%H%M%S')}"
      backup_path = File.join(@backup_dir, backup_name)
      FileUtils.mv(path, backup_path)
      progress.log("Backed up #{path} to #{backup_path}")
    end

    def remove_repo
      FileUtils.rm_rf(@target_dir) if File.directory?(@target_dir)
    end

    def remove_symlink(item)
      target = File.expand_path(item[:target])
      return unless File.symlink?(target)

      FileUtils.rm(target)

      # Restore backup if exists
      restore_backup(target)
    end

    def restore_backup(target)
      basename = File.basename(target)
      backups = Dir.glob(File.join(@backup_dir, "#{basename}.*")).sort
      return if backups.empty?

      latest_backup = backups.last
      FileUtils.mv(latest_backup, target)
      progress.log("Restored #{target} from backup")
    end
  end

  Registry.register(:dotfiles, DotfilesInstaller,
    description: 'Clone and symlink dotfiles',
    order: 5) # Run first, before everything
end

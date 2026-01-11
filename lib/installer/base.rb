# frozen_string_literal: true

require 'json'
require 'fileutils'

module Installer
  # Base class for all installer tasks with uninstall support
  class Base
    STATE_DIR = File.expand_path('~/.macos_installer')

    attr_reader :name, :progress, :installed_items

    def initialize(name)
      @name = name
      @installed_items = []
      @progress = Progress.new(name)
      ensure_state_dir
    end

    # Override in subclasses
    def install
      raise NotImplementedError, "#{self.class} must implement #install"
    end

    # Override in subclasses
    def uninstall(item)
      raise NotImplementedError, "#{self.class} must implement #uninstall"
    end

    # Override in subclasses
    def installed?(item)
      raise NotImplementedError, "#{self.class} must implement #installed?"
    end

    def uninstall_all
      progress.start_uninstall
      load_state

      @installed_items.reverse.each do |item|
        begin
          progress.log("Uninstalling: #{item[:name]}")
          uninstall(item)
          progress.item_uninstalled(item[:name])
        rescue StandardError => e
          progress.error("Failed to uninstall #{item[:name]}: #{e.message}")
        end
      end

      clear_state
      progress.complete_uninstall
    end

    protected

    def record_installation(item_name, metadata = {})
      item = { name: item_name, installed_at: Time.now.iso8601 }.merge(metadata)
      @installed_items << item
      save_state
      progress.item_completed(item_name)
    end

    def skip_if_installed(item_name)
      if installed?(item_name)
        progress.item_skipped(item_name)
        true
      else
        false
      end
    end

    private

    def state_file
      File.join(STATE_DIR, "#{@name}_state.json")
    end

    def ensure_state_dir
      FileUtils.mkdir_p(STATE_DIR)
    end

    def save_state
      File.write(state_file, JSON.pretty_generate({
        name: @name,
        installed_items: @installed_items,
        last_updated: Time.now.iso8601
      }))
    end

    def load_state
      return unless File.exist?(state_file)

      data = JSON.parse(File.read(state_file), symbolize_names: true)
      @installed_items = data[:installed_items] || []
    rescue JSON::ParserError
      @installed_items = []
    end

    def clear_state
      FileUtils.rm_f(state_file)
      @installed_items = []
    end
  end
end

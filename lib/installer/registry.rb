# frozen_string_literal: true

module Installer
  # Registry for installer plugins - enables future extensibility
  class Registry
    class << self
      def installers
        @installers ||= {}
      end

      def register(name, klass, options = {})
        installers[name.to_sym] = {
          class: klass,
          description: options[:description] || "Install #{name}",
          dependencies: options[:dependencies] || [],
          order: options[:order] || 100
        }
      end

      def get(name)
        installers[name.to_sym]
      end

      def all
        installers.sort_by { |_, v| v[:order] }
      end

      def names
        all.map(&:first)
      end

      def create(name, config)
        entry = get(name)
        raise ArgumentError, "Unknown installer: #{name}" unless entry

        entry[:class].new(config)
      end

      def check_dependencies(name)
        entry = get(name)
        return [] unless entry

        missing = entry[:dependencies].reject do |dep|
          Command.which(dep)
        end

        missing
      end
    end
  end
end

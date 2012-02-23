class Pry
  class Plugins
    PREFIX = /^pry-/
    Gem.refresh
    
    class << self
      @@disabled, @@enabled, @@list = [], {}, []

      def disabled; @@disabled.dup end
      def list; @@list end
      def enabled; @@enabled.dup end
      def prefix; PREFIX end

      def disable value
        if !value.empty?
          @@disabled.push(value)
        end
      end

      def define_plugin name = nil, info, &block
        if info.is_a?(Hash)
          if block && name
            plugin = Pry::Plugins.const_set(plugin, Class.new(Pry::Plugin, &block))
          else
            if !block && name || !name && block
              return warn 'Unable to define a plugin without both a PluginName an a it\'s block.'
            end
          end
        end
      end

      def run name = true, info
        if name.is_a?(TrueClass)
          Gem::Specification.reject { |gem| gem.name !~ /\A#{prefix}/ }.each do |gem|
            begin
              require gem.name
            rescue => error
              unless error.message.empty?
                Warn error.message
              end
            end
          end
        end
      end
    end
  end

  # Inherit.
  class Plugin
    class << self
      %w(printable_name plugin_name version).each do |meth|
        self.class_eval <<-EVAL
          def #{meth} value = nil
            if value && !value.empty?
              @#{meth} = value
            end

            @#{meth}
          end
        EVAL
      end

      def inherited(subclass)
        $stdout.puts subclass
        Pry::Plugins.list.push subclass
      end
    end
  end
end
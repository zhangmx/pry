class Pry
  class Plugins
    PREFIX = /^pry-/
    Gem.refresh

    @disabled, @enabled, @plugins = [], {}, {}
    class << self
      def plugins; @plugins.dup end
      def prefix; PREFIX end
      def enabled; @enabled.dup end
      def disabled; @disabled.dup end

      def disable value
        if !value.empty?
          @disabled.push(value)
        end
      end

      @user_disabled = Pry.config.disabled_plugins

      if @user_disabled.is_a? String
        # Thanks ducanbeevers for spotting this bug.
        @user_disabled = @user_disabled.split /,\s*/
      end

      @user_disabled.to_a.each { |plugin| disable plugin }

      def define_plugin name = nil, info, &block
        if info.is_a? Hash
          if block && name
            plugin = Pry::Plugins.const_set(plugin, Class.new(Pry::Plugin, &block))
          else
            if !block && name || !name && block
              return warn 'Unable to define a plugin without both a PluginName an a it\'s block.'
            end
          end
        end
      end

      def run
        Gem::Specification.reject { |gem| gem.name !~ /\A#{prefix}/ }.each do |plugin|
          begin
            unless @plugins[plugin.name].is_a? Hash
              @plugins[plugin.name] = {
                :homepage => plugin.homepage,
                :name => plugin.name,
                :version => plugin.version.to_s 
              }
            end

            unless plugin.activated?
              require @plugins[plugin.name][:name]
            end
          rescue => error
            if error.message =~ /\ABailing/
              return raise RuntimeError, error.message, 'Pry'
            end

            @plugins.delete(plugin.name)
            warn "Plugin not loaded received an error: #{error.message}"
          end
        end
      end
    end
  end

  # Inherit.
  class Plugin
    class << self
      attr_reader :version

      protected
      def define_plugin plugin_name, plugin_description = nil, plugin_version = nil
        plugin_version = @version if plugin_version.nil?
        const_set(:VERSION, plugin_version)
        @version = plugin_version
        
        if Pry::Plugins.plugins[plugin_name].nil?
          return raise "Bailing #{plugin_name} does not match gem."
        end

        Pry::Plugins.class_eval <<-EVAL
          @enabled["#{plugin_name}"] = @plugins["#{plugin_name}"].merge(
            :version => "#{plugin_version}",
            :name => "#{plugin_name}",
            :constant => #{name},
            :description => "#{plugin_description}") { |key, old, new| if new.nil?; old else; new end }
        EVAL
      end
    end
  end
end

Pry::Plugins.run
# A ready to build gem that is already deployed for this plugin system:
# https://github.com/envygeeks/pry-vterm_aliases/tree/pry/plugin_system

class Pry
  class Plugins
    PREFIX = /^pry-/
    Gem.refresh
    Pry::Plugins.const_set(:User, Class.new)

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

      def define_plugin plugin_name, &block
        if block && plugin_name
          begin
            @enabled[plugin_name.downcase] = @plugins[plugin_name.downcase] = {
              :user_plugin => true,
              :plugin_instance => Pry::Plugins::User.const_set(plugin_name, Class.new(Pry::UserPlugin, &block))
            }
          rescue => error
            @enabled.delete(plugin_name.downcase)
            @plugins.delete(plugin_name.downcase)
            warn "Unable to create plugin received an error: #{error.message}"
          end
        else
          if !block && plugin_name || !plugin_name && block
            return warn 'Unable to define a plugin without both a PluginName an a it\'s block.'
          end
        end
      end

      def run
        Gem::Specification.reject { |gem| gem.name !~ /\A#{prefix}/ }.each do |plugin|
          begin
            unless @plugins[plugin.name].is_a? Hash
              @plugins[plugin.name] = {
                :plugin_homepage => plugin.homepage,
                :plugin_name => plugin.name,
                :plugin_author => plugin.author,
                :plugin_user_plugin => false,
                :plugin_version => plugin.version.to_s,
                :plugin_description => plugin.description,
              }
            end

            unless plugin.activated?
              require @plugins[plugin.name][:plugin_name]
            end
          rescue => error
            return raise RuntimeError, error.message, 'Pry' if error.message =~ /\ABailing/
            @plugins.delete(plugin.name)
            warn "Plugin not loaded received an error: #{error.message} -- #{caller[1]}"
          end
        end

        @plugins.each do |plugin_name, plugin|
          unless @enabled[plugin_name]
            @enabled[plugin_name] = plugin.merge!(:legacy => true)
          else
            if plugin[:plugin_constant].is_a? Class
              begin @enabled[plugin_name][:plugin_instance] = plugin[:plugin_instance] = plugin[:plugin_constant].new
              rescue
                # Just to be sure, sometimes it can happen....
                plugin.delete :plugin_instance
                @enabled[plugin_name].delete :plugin_instance
              end
            end
          end
        end
      end
    end
  end

  # Inherit.
  class UserPlugin
    class << self
      attr_reader :plugin_name, :plugin_version, :plugin_homepage
      attr_reader :plugin_description, :plugin_author
      attr_reader :version
      
      protected
      # Mock define_plugin for copy and paste repl testing but modify it a tiny bit.
      def define_plugin plugin_name, plugin_description = nil, plugin_version = nil
        if Gem::Version.correct?(plugin_description)
          plugin_version, plugin_description = plugin_description, nil
        end

        plugin_version = @version if plugin_version.nil?
        const_set(:VERSION, plugin_version)
        @plugin_author = 'You'
        @plugin_name = name.to_s.downcase
        @plugin_description = plugin_description
        @plugin_version = @version = plugin_version
        @plugin_homepage = 'http://localhost.localdomain'
      end
    end
  end

  # Inherit.
  class Plugin
    class << self
      attr_reader :plugin_name, :plugin_version, :plugin_homepage
      attr_reader :plugin_description, :plugin_author
      attr_reader :version

      protected
      def define_plugin plugin_name, plugin_description = nil, plugin_version = nil
        return raise "Bailing #{plugin_name} does not match gem." if (ext_plugin = Pry::Plugins.plugins[plugin_name]).nil?
        plugin_version, plugin_description = plugin_description, nil if plugin_description == ext_plugin[:plugin_version]
        @plugin_version = @version = ext_plugin[:plugin_version] if plugin_version.nil?
        @plugin_description = plugin_description
        @plugin_description = ext_plugin[:plugin_description] if @plugin_description.nil?

        const_set(:VERSION, @version)
        @plugin_name = plugin_name
        @plugin_author = ext_plugin[:plugin_author]
        @plugin_homepage = ext_plugin[:plugin_homepage]

        Pry::Plugins.class_eval <<-EVAL
          @enabled["#{plugin_name}"] = @plugins["#{plugin_name}"].merge!({
            :plugin_version => "#{plugin_version}",
            :plugin_name => "#{plugin_name}",
            :plugin_constant => #{name},
            :plugin_description => "#{plugin_description}"
          }) { |key, old, new| if new.nil?; old else; new end }
        EVAL
      end
    end
  end
end

Pry::Plugins.run
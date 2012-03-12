# A ready to build gem that is already deployed for this plugin system:
# https://github.com/envygeeks/pry-vterm_aliases/tree/pry/plugin_system

##
# Tl;dr merge this fucking plugin because it doesn't break anything at all, only adds features ontop of Pry.

##
# The goal of this plugin is not to change the way pry acts with plugins, or reacts to plugins, just to add
# features to plugins, features we will soon maybe want, such as tracking the instances, information about
# plugins being merged in directly from the gemspec, centralizing plugin information to kill off the redundancy
# we have... and so forth.  The original idea was to also allow hook based loading, but this is infeasable at
# this point since no plugin really needs it, but there will be two hook points, load first and load last. It's
# the same principle as load first init last but in this case it's going to be hook based (only to the plugin
# system and not the author) where a plugin can use the pre-defined methods MyPlugin.first (on self obviously)
# and MyPlugin#last (on the instance obviously -- but it will fall back to .last for classes that hide :new.)
# It also adds a few optional and nifty features such as define_plugin but this isn't needed at all, but it's
# recommended for the author to use it if they want to override the few things we allow them to override such
# as the description shown when you type the command 'help'.
#
# The reason I separate User Space Plugins and Top Level Plugins is because there needs to be an audit trail
# not for us, but for the user.  Clearly they could just monkey patch the class but that is on them if they
# chose to do that, the way we do it is keeping it in UserPlugins and Plugins so each can be clearly traced
# back to it's origin, because sometimes tracing shit back to a monkey patch can be pretty damn complicated
# and our goal should be to make it simple, not complicated and this plugin system is designed to be extensible
# and simple, not complicated.
#
# As it stands right now, this plugin system replicates every feature (apart from the way users interact with
# it via ~/.pryrc) of the current plugin system while adding the new features.  It requires no modifications to
# current plugins and will never require any modifications to current gems and uses almost the same amount of
# code which means that well why not just try it? It's not slower, it does not hinder and what it does is mostly
# behind the scenes for Pry itself.


class Pry
  class Plugins
    PREFIX = /^pry-/

    Pry::Config.plugins = OpenStruct.new
    Pry::Config.user = OpenStruct.new
    Pry::Plugins.const_set(:User, Class.new)

    @disabled, @enabled, @plugins = [], {}, {}
    class << self
      def plugins; @plugins.dup end
      def prefix; PREFIX end
      def enabled; @enabled.dup end
      def disabled; @disabled.dup end

      def disable(*values)
        values.each do |value|
          if !value.empty? && value.is_a?(String)
            @disabled.push(value)
          else
            warn "Invalid plugin name #{value}, ignored."
          end
        end
      end
      alias :disable :disable!

      if (@config_disabled = Pry.config.plugins.disabled).is_a? String
        # Thanks Ducanbeevers for spotting this bug.....
        @config_disabled = @config_disabled.split /,\s*/
      else
        if !@config_disabled.is_a? Array
          @config_disabled = []
          warn "A #{@config_disabled.class} is not accept for disabled plugins"
        end
      end

      @config_disabled.to_a.each { |plugin| disable plugin }
      remove_instance_variable(:@config_disabled)

      def(define_plugin plugin_name, &block)
        if block && plugin_name
          begin
            @enabled[plugin_name.downcase] = @plugins[plugin_name.downcase] = {
              :plugin_user_plugin => true,
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

      def load
      Gem.refresh
      
        Gem::Specification.reject { |gem| gem.name !~ /\A#{prefix}/ }.each do |plugin|
          unless @user_disabled.include?(plugin.name)
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
        end
      end
      
      def start
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
      def define_plugin(plugin_name, plugin_description = nil, plugin_version = nil)
        if Gem::Version.correct?(plugin_description)
          plugin_version, plugin_description = plugin_description, nil
        end

        plugin_version = @version if plugin_version.nil?
        const_set(:VERSION, plugin_version)
        
        @plugin_author = Pry::Config.user.name || (ENV['USERNAME'] || '').capitalize
        @plugin_author = 'You' if @plugin_author.nil? || @plugin_author.empty?
        @plugin_name = name.to_s.downcase
        @plugin_description = plugin_description
        @plugin_version = @version = plugin_version
        @plugin_homepage = Pry::Config.user.homepage || 'http://localhost.localdomain'
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
      def define_plugin(plugin_name, plugin_description = nil, plugin_version = nil)
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

Pry::Plugins.load
Pry::Plugins.start
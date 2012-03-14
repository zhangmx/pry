class Pry
  module Plugin
    module Manager
      @acceptable_opts = [:version, :name, :description]
      @blacklist, @enabled, @plugins = [], {}, {}

      class << self
        attr_accessor :prefix
        @prefix = /\Apry-/

        ##
        # Exists as a compability layer, I am no fan of these constants laying around when we should
        # clearly give users the abilty to modify things to their needs if we can.  I would prefer
        # we kill this constant.

        PREFIX = @prefix

        def loaded?(p)
          @plugins.has_key?(p)
        end
      
        def enabled
          @enabled.dup
        end

        ##
        # Validate opts sits as the option validator for Pry::Plugin.define_plugin and it's sister.
        # It's an internal function that uses @acceptable_opts to validate that there are no extra
        # options sent and that version is valid.
        #
        # Arguments: opts (Hash)
        # Method: Validate Opts
        # Internal: Yes
        # Requires eq: Yes, converts string keys to hash keys.
        # Ruby1.8 Compatible: Unknown, inject({}) known to fail.

        def validate_opts(opts)
          opts = opts.inject({}) do |h, (k, v)|
            if v.nil?
              v = ''
            end

            h.update(k.to_sym => v)
          end

          @acceptable_opts.each do |k|
            unless opts.include?(k)
              raise(RuntimeError, 'Missing required plugin option', 'Pry')
            else
              if k == :version
                if !Gem::Version.correct?(opts[:version])
                  raise(RuntimeError, 'Improper version passed as a plugin options', 'Pry')
                end
              end
            end
          end

          unknown_opts = (opts.keys - @acceptable_opts)
          unless unknown_opts.length == 0
            raise(ArgumentError, "Unknown opts: #{opts.join(', ')}) passed as a plugin options", 'Pry')
          end

          opts
        end

        ##
        # Disable is a method to disable plugis before they even get required.  There is also an
        # alias called disabled! that exists only as a compability layer for old skool users.
        # It accepts unlimited options and does not warn you if a plugin name is invalid, it will
        # simply ignore it.
        #
        # REFACTOR WARNING: This could be refactored within minutes of it's initial commit or even
        # the night after.  There is strong debate between Jordon and Jordon over whether to raise
        # or warn if a plugin name is invalid and rejected for inclusion.  Unless a fight breaks
        # out and one of the Jordon's ends up dead you will have a decision about this soon.
        #
        # Arguments: *values (strings)
        # Method: Pry::Plugins.disable
        # Internal: No
        # Requires eq: No
        # Simple usage: Pry::Plugins.disable 'pry-plugin_name1, pry-plugin_name2'
        # Simple usage: Pry::Plugins.disable 'pry-plugin_name1', 'pry-plugin_name2'

        def disable(*values)
          values.map(&:to_s).each do |value|
            if !value.empty? && value !~ /\s/ && value !~ /\A\d+\Z/
              @blacklist.push(value)
            end
          end
        end
        alias :disable :disable!

        if (@disabled = Pry.config.plugins.disabled).is_a?(String)
          @disabled = @disabled.split(/,\s*/)
        else
          if !@disabled.is_a?(Array)
            @disabled = []
            warn "A #{@config_disabled.class} is not accepted for disabled plugins"
          end
        end

        # Define is a public but somewhat internal method for defining a plugin in the user space
        # of Pry.  It is preferred that users use define-plugin % &block when the command is
        # added to Pry.  The main reason it is considered public but somewhat internal is that
        # the second argument is always considered empty and therefore a clone of name in downcase
        # form.  Any user who uses this method should never define a second argument as it will
        # raise.
        #
        # There are some major differences to note about user space plugins in that user space
        # plugins have no known information other then the constant name and it's instance. This
        # could change and be reverted to it's earlier state where it did assume some of it and
        # send it up, but until there is an elegent way discussed about the Pry.config options
        # it's derived from this will be left out.
        #
        # REFACTOR WARNING: Jordon and Jordon are currently debating doing this like class_eval
        # where we will accept both a string source and a block (either or) so the API could
        # change to add that, but it won't affect current usages any as any Ruby programmer knows.
        #
        # Arguments:
        #  * name (string) -- The name of your plugin (use ClassCaps)
        #  * lower_name (string) -- Internal
        #  * &block the source of your plugin (can use anything available to normal plugins)
        # Method: Validate Opts
        # Internal: Yes
        # Requires eq: Yes, converts string keys to hash keys.
        # Ruby1.8 Compatible: Unknown, inject({}) known to fail.


        def define(name, lower_name = name.downcase, &block)
          if block && name && lower_name == name.downcase
            begin
              @enabled[lower_name] = @plugins[lower_name] = {
                :user_plugin => true,
                :instance => Pry::Plugins::User.const_set(name, Class.new(Pry::Plugin::Base, &block))
              }
            rescue => error
              @enabled.delete(lower_name)
              @plugins.delete(lower_name)
              warn "Unable to create plugin received an error: #{error.message}"
            end
          else
            if !block && name || !name && block
              return warn('Unable to define a plugin without both a name an a it\'s block.')
            else
              if name.downcase != lower_name
                raise(ArgumentError, 'wrong number of arguments (2 for 1)')
              end
            end
          end
        end

        ##
        # Load is the internal method for Pry to require all plugins that begin with the prefix.
        # on of the big differences between this loader and Pry's loader is it does not assume
        # the state of prefix by using the constant, it uses instance variable allowing the user
        # to change the prefix to whatever they want.
        #
        # Arguments: None
        # Method: Pry::Plugins.load
        # Internal: Yes
        # Requires eq: No
        # Ruby1.8 Compatible: Unknown, Gem command might fail on some Debian and Fedora systems.

        def load
          @disabled.each { |p| disable(p) }
          remove_instance_variable(:@disabled)
        
          Gem.refresh
          Gem::Specification.reject { |gem| gem.name !~ @prefix }.each do |plugin|
            unless @blacklist.include?(plugin.name)
              begin
                unless @plugins[plugin.name].is_a? Hash
                  @plugins[plugin.name] = {
                    :homepage => plugin.homepage,
                    :author => plugin.author,
                    :name => plugin.name
                    :user_plugin => false,
                    :version => plugin.version.to_s,
                    :description => plugin.description,
                  }
                end

                unless plugin.activated?
                  # Can use plugin.name too, I guess..
                  require @plugins[plugin.name][:name]
                end
              rescue => error
                if error.message =~ /\ABailing/
                  return raise RuntimeError, error.message, 'Pry'
                end

                @plugins.delete(plugin.name)
                warn "Plugin not loaded received an error: #{error.message} -- #{caller[1]}"
              end
            end
          end
        end

        ##
        # Start is the internal method for Pry to start plugins that wish to 'load' last.  The
        # idea is that the plugin creates the initialize method and puts anything they need done
        # there and we check for initialize and then ininitialize it just before Pry starts.
        #
        # Arguments: None
        # Method: Pry::Plugins.start
        # Internal: Yes
        # Requires eq: No
        # Ruby1.8 Compatible: Yes.

        def start
          @plugins.each do |name, plugin|
            unless @enabled[name]
              @enabled[name] = plugin.merge!(:legacy => true)
            else
              if plugin[:constant].is_a?(Class) && plugin[:constant].respond_to?(:new)
                begin
                  unless plugin[:instance].instance_of?(plugin[:constant])
                    if plugin[:constant].instance_method(:initialize).owner == plugin[:constant]
                      @enabled[name][:instance] = plugin[:instance] = plugin[:constant].new
                    end
                  end
                rescue
                  plugin.delete(:instance)
                  @enabled[name].delete :instance
                end
              end
            end
          end
        end
      end
    end

    # Extend
    module Helpers
      # Will soon contain command helpers, colour helpers and hook helpers
    end

    # Inherit
    class Base
      class << self
        protected
        def define_plugin(opts)
          opts = Pry::Plugin::Manager.validate_opts(opts)
          if Pry::Plugin::Manager.loaded?(opts[:name])
            return raise "Bailing #{opts[:name]} does not match gem."
          end

          unless defined?(@version)
            attr_reader :version
            @version = opts[:version]
          end

          const_set(:VERSION, opts[:version]) unless defined?(VERSION)
          Pry::Plugin::Manager.class_eval <<-EVAL
            @enabled["#{opts[:name]}"] = @plugins["#{opts[:name]}"].merge!({
              :version => "#{opts[:version]}",
              :name => "#{opts[:name]}",
              :constant => #{name},
              :description => "#{opts[:description]}"
            }) { |key, old, new| if new.nil?; old else; new end }
          EVAL
        end
      end
    end
    
    class << self
      def define(*args, &block)
        Manager.define(*args, &block)
      end
    end
  end
end

# This gets loaded early.
Pry::Plugin::Manager.load if defined?(Pry::Plugin::Manager)

# This gets loaded at the very end of everything.
if defined?(Pry::Plugin::Manager) && Pry::Plugin::Manager.respond_to?(:start)
  Pry::Plugin::Manager.start
end

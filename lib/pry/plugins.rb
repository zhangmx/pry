class Pry
  class Plugins
    # Depricate IMO.
    PREFIX = /^pry-/
    
    class << self
      @@disabled, @@enabled, @@list = [], {}, []

      def disabled; @@disabled end
      def list; @@list end
      def enabled; @@enabled end
      def prefix; PREFIX end

      def disable value
        if !value.empty?
          @@disabled.push(value)
        end
      end

      # For REPL/Pryrc Plugins.
      # Not required for Pryrc.
      def define_plugin plugin, &block
        if block
          plugin = Pry::Plugins.const_set(plugin, Class.new(Pry::Plugin, &block))
        end

        if plugin.class == OpenStruct
          plugin.new = plugin.instance
        end

        # Soon to be modified to accept file_name.
        @@enabled[plugin.plugin_name] = {
          :listing => plugin.listing,
          :version => plugin.version,
          :instance => plugin.new,
          :plugin_name => plugin.plugin_name,
        }
      end

      def run
        Gem.refresh
        Hash[Gem.source_index.each.to_a].delete_if { |package, gem| package !~ /\A#{PREFIX}/ }.each do |package, gem|
          begin; require gem.name; rescue => error; Warn error.message unless error.message.empty? end
        end
      end
    end
  end

  # Inherit.
  class Plugin
    class << self
      # Alias VERSION to version if you like...
      %w(printable_name version).each do |meth|
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
        Pry::Plugins.list.push subclass
      end
    end
  end

  class PluginManager
    PRY_PLUGIN_PREFIX = /^pry-/

    # Placeholder when no associated gem found, displays warning
    class NoPlugin
      def initialize(name)
        @name = name
      end

      def method_missing(*args)
        warn "Warning: The plugin '#{@name}' was not found! (no gem found)"
      end
    end

    class Plugin
      attr_accessor :name, :gem_name, :enabled, :spec, :active

      def initialize(name, gem_name, spec, enabled)
        @name, @gem_name, @enabled, @spec = name, gem_name, enabled, spec
      end

      # Disable a plugin. (prevents plugin from being loaded, cannot
      # disable an already activated plugin)
      def disable!
        self.enabled = false
      end

      # Enable a plugin. (does not load it immediately but puts on
      # 'white list' to be loaded)
      def enable!
        self.enabled = true
      end

      # Load the Command line options defined by this plugin (if they exist)
      def load_cli_options
        cli_options_file = File.join(spec.full_gem_path, "lib/#{spec.name}/cli.rb")
        require cli_options_file if File.exists?(cli_options_file)
      end
      # Activate the plugin (require the gem - enables/loads the
      # plugin immediately at point of call, even if plugin is
      # disabled)
      # Does not reload plugin if it's already active.
      def activate!
        begin
          require gem_name if !active?
        rescue LoadError => e
          warn "Warning: The plugin '#{gem_name}' was not found! (gem found but could not be loaded)"
          warn e
        end
        self.active = true
        self.enabled = true
      end

      alias active? active
      alias enabled? enabled
    end

    def initialize
      @plugins = []
    end

    # Find all installed Pry plugins and store them in an internal array.
    def locate_plugins
      Gem.refresh
      (Gem::Specification.respond_to?(:each) ? Gem::Specification : Gem.source_index.find_name('')).each do |gem|
        next if gem.name !~ PRY_PLUGIN_PREFIX
        plugin_name = gem.name.split('-', 2).last
        @plugins << Plugin.new(plugin_name, gem.name, gem, true) if !gem_located?(gem.name)
      end
      @plugins
    end

    # @return [Hash] A hash with all plugin names (minus the 'pry-') as
    #   keys and Plugin objects as values.
    def plugins
      h = Hash.new { |_, key| NoPlugin.new(key) }
      @plugins.each do |plugin|
        h[plugin.name] = plugin
      end
      h
    end

    # Require all enabled plugins, disabled plugins are skipped.
    def load_plugins
      @plugins.each do |plugin|
        plugin.activate! if plugin.enabled?
      end
    end

    private
    def gem_located?(gem_name)
      @plugins.any? { |plugin| plugin.gem_name == gem_name }
    end
  end

end


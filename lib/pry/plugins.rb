require 'net/http'
require 'uri'
require 'yaml'

class Pry
  class PluginManager

    # The prefix used to distinguish Pry plugins from other gems. Name your gem
    # with this prefix to allow it to be used as a plugin.
    PRY_PLUGIN_PREFIX = "pry-"

    # The API endpoint address for plugins.
    PLUGINS_HOST = "https://rubygems.org"

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
        self.active = false
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
        # Create the configuration object for the plugin.
        Pry.config.send("#{gem_name.gsub('-', '_')}=", OpenStruct.new)

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

    RemotePlugin = Struct.new(:name, :gem_name, :data) do
      def method_missing(method, *args, &block)
        if data.has_key?(key = method.to_s)
          data[key]
        else
          super
        end
      end
    end

    class << self
      # Just a shortcut.
      def text
        Pry::Helpers::Text
      end
      private :text

      # Display a list of all installed plugins.
      #
      # @param [Hash{String => PluginManager::Plugin}] plugins The Array of
      #   installed plugins.
      # @param [IO] output The output stream.
      # @return [void]
      def show_installed_plugins(plugins, output = Pry.config.output)
        plugins_list = []
        plugins_list << "Installed Plugins:" << "--"

        plugins.each do |name, plugin|
          plugins_list << "#{ name }".ljust(18) + plugin.spec.summary
        end

        Helpers::BaseHelpers.stagger_output plugins_list.join("\n"), output
      end

      # Display a list of all remote plugins. Remote plugins are Ruby gems that
      # start with {PluginManager::PRY_PLUGIN_PREFIX plugin prefix}.
      #
      # @param [Hash{String => PluginManager::RemotePlugin}] plugins The array of
      #   remote plugins.
      # @param [IO] output The output stream.
      # @return [void]
      def show_remote_plugins(plugins, output = Pry.config.output)
        plugins_list = []
        plugins_list << "Remote Plugins:" << "--"

        # Exclude Pry's dependencies and Pry itself, because they're already
        # installed in the system (you won't be able to use Pry otherwise).
        exclude_deps = Gem::Specification.find_by_name("pry").dependencies.map(&:name)
        exclude_deps << "pry"

        plugins.each_with_index do |(name, plugin), index|
          index += 1
          name = text.bold(name.ljust(4))
          deps = plugin.dependencies["runtime"].map { |dep| dep["name"]  } - exclude_deps
          info = text.indent(text.wrap(plugin.info, 74), 6)

          unless deps.empty?
            dependencies = text.indent("\n\nDependencies:\n", 6)
            dependencies << text.indent(text.wrap(deps.join(", "), 72), 8)
          end

          entry = [index, ". ", name, "\n", info, dependencies].join

          plugins_list << entry
        end

        Helpers::BaseHelpers.stagger_output plugins_list.join("\n"), output
      end
    end

    def initialize
      @plugins = []
      @remote_plugins = []
    end

    # Dispatcher for the plugin location.
    #
    # @param [Symbol] place The place where to locate plugins, `:local` or
    #   `remote`
    # @return [void]
    def locate_plugins(place = :local)
      case place
      when :local
        find_local_plugins
      when :remote
        find_remote_plugins
      end
    end

    # Finds all installed Pry plugins and stores them in an internal array.
    #
    # @return [Array<PluginManager::Plugin>] The Array of all installed plugins.
    def find_local_plugins
      Gem.refresh

      gems = if Gem::Specification.respond_to?(:each)
               Gem::Specification
             else
               Gem.source_index.find_name('')
             end

      gems.each do |gem|
        gem_name = gem.name
        next if gem_name !~ /^#{ PRY_PLUGIN_PREFIX }/
        plugin_name = extract_plugin_name(gem_name)

        unless gem_located?(gem_name)
          @plugins << Plugin.new(plugin_name, gem_name, gem, true)
        end
      end

      @plugins
    end

    # Finds all remote plugins. The method communicates with Rubygems API in
    # order to fetch all gems that start with {PluginManager::PRY_PLUGIN_PREFIX}
    # and stores them in an internal array.
    #
    # @return [Array<PluginManager::RemotePlugin>] The Array of all remote
    #   Pry plugins.
    def find_remote_plugins
      path = "/api/v1/search.yaml?query=#{ PRY_PLUGIN_PREFIX }"
      uri = URI.parse([PLUGINS_HOST, path].join)

      request = Net::HTTP::Get.new(uri.request_uri)
      request.add_field "Connection", "keep-alive"
      request.add_field "Keep-Alive", "15"
      request.content_type = "application/x-www-form-urlencoded"

      connection = Net::HTTP.new(uri.host, uri.port)
      if uri.scheme == "https"
        require 'net/https'
        connection.use_ssl = true
        connection.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      connection.start

      response = connection.request(request)
      YAML.load(response.body).each do |gem|
        plugin_name = extract_plugin_name(gem["name"])
        @remote_plugins << RemotePlugin.new(plugin_name, gem["name"], gem)
      end

      @remote_plugins
    end

    # @return [Hash{String => PluginManager::Plugin>]
    # @see #_plugins
    def plugins
      _plugins(:place => :local)
    end

    # @return [Hash{String => PluginManager::RemotePlugin>]
    # @see #_plugins
    def remote_plugins
      _plugins(:place => :remote)
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

    # @example
    #   extract_plugin_name("pry-the-plugin")
    #   # => "the-plugin"
    # @return [String] The name of the plugin without its prefix.
    def extract_plugin_name(name)
      name.split('-', 2).last
    end

    # @param [Hash] options The options hash.
    # @option options [Symbol] :place (:local) The plugins to be returned.
    # @return [Hash{String => PluginManager::<Plugin,RemotePlugin>}] A hash with
    #   all plugin names (minus the 'pry-') as keys and Plugin or RemotePlugin
    #   objects as values.
    def _plugins(options = {})
      place = options.fetch(:place, :local)

      h = Hash.new { |_, key| NoPlugin.new(key) }
      (place == :remote ? @remote_plugins : @plugins).each do |plugin|
        h[plugin.name] = plugin
      end
      h
    end

  end

end

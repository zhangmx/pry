class Pry
  module DefaultCommands
    Misc = Pry::CommandSet.new do

      command "toggle-color", "Toggle syntax highlighting." do
        Pry.color = !Pry.color
        output.puts "Syntax highlighting #{Pry.color ? "on" : "off"}"
      end

      command "simple-prompt", "Toggle the simple prompt." do
        case _pry_.prompt
        when Pry::SIMPLE_PROMPT
          _pry_.pop_prompt
        else
          _pry_.push_prompt Pry::SIMPLE_PROMPT
        end
      end

      command "pry-version", "Show Pry version." do
        output.puts "Pry version: #{Pry::VERSION} on Ruby #{RUBY_VERSION}."
      end

      command "reload-method", "Reload the source file that contains the specified method" do |meth_name|
        meth = get_method_or_raise(meth_name, target, {}, :omit_help)

        if meth.source_type == :c
          raise CommandError, "Can't reload a C method."
        elsif meth.dynamically_defined?
          raise CommandError, "Can't reload an eval method."
        else
          file_name = meth.source_file
          load file_name
          output.puts "Reloaded #{file_name}."
        end
      end

      create_command "plugin" do
        description "Manage Pry plugins"

        banner <<-BANNER
          Usage: plugin
        BANNER

        def subcommands(cmd)
          cmd.on :list do |opt|
            opt.on :r, "remote", "Show the list of all available plugins"
            opt.on :f, "force",  "Refresh cached list of remote plugins"

            opt.add_callback(:empty) { show_installed_plugins }
          end

          cmd.on :status do |opt|
            opt.on :a, "active", "Show only active plugins"
            opt.on :i, "inactive", "Show only inactive plugins"

            opt.add_callback(:empty) { show_plugins_with_status_of(:any) }
          end
        end

        def process
          # Process "list" subcommand.
          list = opts[:list]
          show_remote = list.present?(:remote)
          force       = list.present?(:force) && show_remote

          # Process "status" subcommand.
          status = opts[:status]
          show_active   = status.present?(:active) or
          show_inactive = status.present?(:inactive)

          # Decide what to execute.
          show_remote_plugins(force) if show_remote
          show_plugins_with_status_of(:active) if show_active
          show_plugins_with_status_of(:inactive) if show_inactive
        end

        private

        # @see {PluginManager.show_installed_plugins}
        # @return [void]
        def show_installed_plugins
          PluginManager.show_installed_plugins(Pry.plugins)
        end

        # Displays the list of remote plugins. Fetches the list of remote Pry
        # plugins if #{Pry.remote_plugins} hash is empty.
        #
        # @param [Boolean] force The flag, which specifies whether the list of
        #   remote plugins should be refreshed or not. If not, then it recalls
        #   {PluginManager#find_remote_plugins} method.
        # @return [void]
        def show_remote_plugins(force = false)
          Pry.locate_plugins(:remote) if Pry.remote_plugins.empty? || force
          PluginManager.show_remote_plugins(Pry.remote_plugins)
        end

        # Displays the list of local plugins in conjunction with their status
        # label (active or inactive). If +status+ is +:active+ or +:inactive+,
        # the label doesn't get appended.
        #
        # If +status+ is +:active+, then the method prints only the list of
        # currently active plugins.
        #
        # If +status+ is +:inactive+, then the method prints only the list of
        # currently inactive plugins.
        #
        # @param [Symbol] status +:active+, +:inactive+, +:all+
        # @return [void]
        def show_plugins_with_status_of(status = :any)
          list = []

          type = case status
                 when :active
                   list << "Active Plugins:"
                   true
                 when :inactive
                   list << "Inactive Plugins:"
                   false
                 else
                   list << "Plugin Statuses:"
                 end
          list << "--"

          Pry.locate_plugins
          Pry.plugins.each do |name, plugin|
            if any = status == :any or plugin.active? == type
              # Add label only if we display the list of all plugins in a jumble.
              if any
                label = plugin.active? ? "(active)" : "(inactive)"
              end

              list << [name, label].join(" ")
            end
          end

          Pager.page list.join("\n")
        end

      end
    end
  end
end

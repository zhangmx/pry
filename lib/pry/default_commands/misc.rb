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

        def sub_commands(cmd)
          cmd.on :list do
            on :r, "remote", "Show the list of all available plugins"
            on :f, "force",  "Refresh cached list of remote plugins"

            add_callback(:empty) {
              PluginManager.show_installed_plugins(Pry.plugins)
            }
          end
        end

        def process
          show_remote = opts[:list].present?(:remote)
          force       = show_remote && opts[:list].present?(:force)

          show_remote_plugins(force) if show_remote
        end

        private

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

      end
    end
  end
end

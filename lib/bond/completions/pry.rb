
Pry::Commands.commands.each_value do |command|
  Bond.complete :prefix => /#{command.command_regex}.* /, :anywhere => /.*/, :action => lambda{ |search|
    command.new.complete search
  }
end

Bond.complete :anywhere => /^[a-z\-]+/, :action => lambda{ |search|
  Pry::Commands.commands.values.map(&:name).grep(String)
}

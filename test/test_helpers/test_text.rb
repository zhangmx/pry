require 'helper'

describe Pry::Helpers::Text do
  before do
    @h = Pry::Helpers::Text
  end

  describe 'wrap method' do
    before do
      @poem = "Don't ask me why alone in dismal thought in times of mirth, I'm often filled with strife, and why my weary stare is so distraught, and why I don't enjoy the dream of life."
    end

    it 'should wrap strings longer that 80 characters by default' do
      wrapped_poem = @h.wrap(@poem)
      wrapped_poem.should == "Don't ask me why alone in dismal thought in times of mirth, I'm often filled\nwith strife, and why my weary stare is so distraught, and why I don't enjoy the\ndream of life."
    end

    it 'should wrap strings longer than +line_width+ characters' do
      wrapped_poem = @h.wrap(@poem, 48)
      wrapped_poem.should == "Don't ask me why alone in dismal thought in\ntimes of mirth, I'm often filled with strife,\nand why my weary stare is so distraught, and why\nI don't enjoy the dream of life."
    end

    it 'should not wrap short strings' do
      poem = @h.wrap("I was there, drank beer and mead, barely got my mustache wet.")
      poem.should == "I was there, drank beer and mead, barely got my mustache wet."
    end
  end
end

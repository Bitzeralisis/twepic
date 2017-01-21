require_relative '../world/thing'

module ConsumeInput

  def consume_input(input, config)
    case input
      # Mouse control
      when Ncurses::KEY_MOUSE
        mouse_event = Ncurses::MEVENT.new
        Ncurses::getmouse(mouse_event)
        consume_mouse_input(mouse_event)

      # Keyboard control
      else
        if @input_header == nil
          action = config.keybinds(self.class)[input]
        else
          action = config.keybinds(self.class)[@input_header][input]
          @input_header = nil
        end

        if action.is_a? Symbol
          method("action_#{action.to_s}").call
          true
        elsif action.is_a? Hash
          @input_header = input
          true
        else
          false
        end
    end
  end

  def consume_mouse_input(input)
    false
  end

end

class Panel < Thing

  include ConsumeInput

  attr_reader :focused

  def initialize
    super
    @focused = false
  end

  def focused=(rhs)
    @focused = rhs
    flag_redraw
  end

end

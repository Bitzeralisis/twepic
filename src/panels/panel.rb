require_relative '../world/thing'

class Panel < Thing

  attr_reader :focused

  def initialize
    super
    @focused = false
  end

  def focused=(rhs)
    @focused = rhs
    flag_redraw
  end

  def consume_input(input)
    false
  end

end

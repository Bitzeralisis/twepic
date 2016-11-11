#!/usr/bin/env ruby

class Coord
  attr_accessor :x, :y
  def initialize(x = 0, y = 0)
    @x, @y = x, y
  end
  def +(rhs)
    Coord.new(x+rhs.x, y+rhs.y)
  end
  def -(rhs)
    Coord.new(x-rhs.x, y-rhs.y)
  end
end

# The most basic object in a world.
# In the world logic loop, :tick, :draw, and :render are called continuously on Things contained in
# the world. :draw will call :redraw if :flag_redraw was set; :render will call :rerender if
# :flag_rerender was set. :tick should be overridden with the bulk of the Thing's logic, including
# determining if the Thing should redraw. :redraw should be overridden with code that involves
# saving what should be rendered, such as drawing to a ncurses pad. :rerender should be overridden
# with code that actually puts what is drawn into the ncurses main screen.
class Thing

  attr_accessor :parent
  attr_accessor :world
  attr_accessor :visible
  attr_accessor :pos    # The position of this object in :parent's local space
  attr_accessor :origin # The position in this Thing's rendering object that corresponds to (0,0) in this Thing's local space
  attr_accessor :clip   # Defines a rectangle with corners :clip and :clip+:size in this Thing's
  attr_reader :size   # local space that the Thing's rendering object will be drawn in
  attr_reader :will_redraw
  attr_reader :will_rerender

  def initialize
    @parent = nil
    @world = nil
    @visible = true
    @pos = Coord.new
    @origin = Coord.new
    @clip = Coord.new
    @size = Coord.new
  end

  def pos=(args)
    @pos = Coord.new(*args)
  end

  def origin=(args)
    @origin = Coord.new(*args)
  end

  def clip=(args)
    @clip = Coord.new(*args)
  end

  def size=(args)
    old_size = @size
    @size = Coord.new(*args)
    on_resize(old_size, @size)
  end

  def global_pos
    @parent.global_pos + @pos
  end

  def visible=(visible)
    flag_rerender if visible && !@visible
    @visible = visible
  end

  def _tick(time)
    tick(time)
  end

  def tick(time)
  end

  def draw
    if (@will_redraw || @will_redraw.nil?) && visible
      redraw
      $draws += 1
      @will_redraw = false
      flag_rerender
      true
    else
      false
    end
  end

  def redraw
  end

  def render
    if @will_rerender && visible
      rerender
      $renders += 1
      @will_rerender = false
      true
    else
      false
    end
  end

  def rerender
  end

  def flag_redraw(redraw = true)
    @will_redraw = redraw
  end

  def flag_rerender(rerender = true)
    @will_rerender = rerender
  end

  def on_resize(old_size, new_size)
  end

end

# A ThingContainer contains Things.
# ThingContainer is most useful when you want a collection of Things to be drawn together.
class ThingContainer < Thing

  def initialize
    super
    @things = []
  end

  def <<(thing)
    thing.parent = self
    thing.world = @world
    @things << thing
  end

  def tick(time)
    super
    @things.each { |thing| thing.tick(time) }
    $ticks += @things.size
  end

  def draw
    drawn = super
    @things.each { |thing| thing.draw } if visible
    drawn
  end

  def render
    rendered = super
    @things.each { |thing| thing.render } if visible
    rendered
  end

  def flag_redraw(redraw = true)
    super
  end

  def flag_rerender(rerender = true)
    super
    @things.each { |thing| thing.flag_rerender(rerender) }
  end

end

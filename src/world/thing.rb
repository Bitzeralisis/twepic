#!/usr/bin/env ruby

# The most basic object in a world.
# In the world logic loop, :tick, :draw, and :render are called continuously on Things contained in
# the world. :draw will call :redraw if :flag_redraw was set; :render will call :rerender if
# :flag_rerender was set. :tick should be overridden with the bulk of the Thing's logic, including
# determining if the Thing should redraw. :redraw should be overridden with code that involves
# saving what should be rendered, such as drawing to a ncurses pad. :rerender should be overridden
# with code that actually puts what is drawn into the ncurses main screen.
class Thing

  attr_accessor :world
  attr_reader :will_redraw
  attr_reader :will_rerender

  def initialize
    @world = nil
  end

  def tick(time)
  end

  def draw
    if @will_redraw || @will_redraw.nil?
      redraw
      @will_redraw = false
      @will_rerender = true
    end
    @will_rerender
  end

  def redraw
  end

  def render(x, y, h, w)
    if @will_rerender
      rerender(x, y, h, w)
      @will_rerender = false
    end
  end

  def rerender(x, y, w, h)
  end

  def flag_redraw(redraw = true)
    @will_redraw = redraw
  end

  def flag_rerender(rerender = true)
    @will_rerender = rerender
  end

end

# A ThingContainer contains Things.
# ThingContainer is most useful when you want a collection of Things to be drawn together.
class ThingContainer < Thing

  def initialize
    @things = []
  end

  def <<(thing)
    thing.world = world
    @things << thing
  end

  def tick(time)
    super(time)
    @things.each { |thing| thing.tick(time) }
  end

  def draw
    super
    @things.each { |thing| thing.draw }
  end

  def render(*args)
    super(*args)
    @things.each { |thing| thing.render(args) }
  end

  def flag_redraw(redraw = true)
    super(redraw)
    @things.each { |thing| thing.flag_redraw(redraw) }
  end

  def flag_rerender(rerender = true)
    super(rerender)
    @things.each { |thing| thing.flag_rerender(rerender) }
  end

end

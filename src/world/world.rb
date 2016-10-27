#!/usr/bin/env ruby

require 'ncursesw'
require 'time'
require_relative 'thing'
require_relative 'window'

# The root Thing in a world.
# By instantiating a World and calling :run, an entire ncurses context will be set up and the world
# will continually process its Things by calling :tick, :draw, and :render on them.
class World < ThingContainer

  include HasWindow

  def initialize
    @things = []
    @quit = false

    self.world = self
  end

  def run
    begin
      # Setup basic ncurses stuff
      Ncurses.initscr
      Ncurses.cbreak
      Ncurses.noecho
      Ncurses.nonl
      Ncurses.stdscr.nodelay(true)
      Ncurses.ESCDELAY = 25
      Ncurses.curs_set(0)
      Ncurses.stdscr.intrflush(false)
      Ncurses.stdscr.keypad(true)

      # Setup mouse stuff
      Ncurses.mousemask(Ncurses::ALL_MOUSE_EVENTS, [])
      Ncurses.mouseinterval(0)

      # Setup color pairs for 1-15 (standard + bright) and 16-231 (216 colors)
      # as that color and black background. Pairs 232-255 free for custom use.
      Ncurses.start_color
      (1..231).each do |i|
        Ncurses.init_pair(i, i, 0)
      end

      @curses_window = Ncurses.stdscr

      # Loop forever
      skip = false
      until @quit
        start = Time.now.to_f
        tick(1)
        draw #unless skip
        render(0, 0, screen_width, screen_height) #unless skip
        len = Time.now.to_f - start
        sleep 0.016-len if len < 0.016 # Update no more than 60 times a second
        skip = len > 0.016 # If the last tick too long then skip the next draw
      end

    ensure
      # Gotta teardown no matter what or else the terminal goes crazy
      Ncurses.echo
      Ncurses.nocbreak
      Ncurses.nl
      Ncurses.endwin
    end
  end

  def rerender(*args)
    Ncurses.doupdate
    Ncurses.stdscr.noutrefresh
  end

  def quit
    @quit = true
  end

end


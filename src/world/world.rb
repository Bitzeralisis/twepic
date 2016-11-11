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
    super
    @parent = nil
    @world = self
    @quit = false
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

      yield

      # Loop forever
      count = 0
      skip = false
      until @quit
        start = Time.now.to_f

        if count == 0
          $logger.debug("60 frames | draws: #{$draws} | renders: #{$renders} | ticks: >#{$ticks}")
          count = 60
          $ticks = 1
          $draws = 0
          $renders = 0
        end
        count -= 1

        tick(1)
        draw #unless skip
        render #unless skip
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

  def global_pos
    Coord.new
  end

  def rerender
    super
    Ncurses.doupdate
    Ncurses.stdscr.noutrefresh
  end

  def flag_rerender
    super
    Ncurses.erase
  end

  def quit
    @quit = true
  end

end


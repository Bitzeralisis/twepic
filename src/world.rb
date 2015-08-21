#!/usr/bin/env ruby

require 'ncursesw'
require 'time'

class Thing

  attr_writer :world

  def initialize
    @world = nil
  end

  def tick
  end

  def draw
  end

end

class World < Thing

  def initialize
    @world = self
    @things = []
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

      # Setup color pairs for 1-15 (standard + bright) and 16-231 (216 colors)
      # as that color and black background. Pairs 232-255 free for custom use.
      Ncurses.start_color
      (1..231).each do |i|
        Ncurses.init_pair(i, i, 0)
      end

      # Loop forever
      skip = false
      while true
        start = Time.now.to_f
        tick
        draw #unless skip
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

  def add(thing)
    thing.world = self
    @things << thing
  end

  def width
    Ncurses.COLS
  end

  def height
    Ncurses.LINES
  end
  
  def getch
    Ncurses.getch
  end

  def color(pair)
    Ncurses.attrset(Ncurses.COLOR_PAIR(pair))
  end

  def color3(r,g,b)
    Ncurses.attrset(Ncurses.COLOR_PAIR(16 + 36*r + 6*g + b))
  end

  def color4(r,g,b,a)
    Ncurses.attrset(Ncurses.COLOR_PAIR(r + 2*g + 4*b + 8*a))
  end

  def bold
    Ncurses.attron(Ncurses::A_BOLD)
  end

  def dim
    Ncurses.attron(Ncurses::A_DIM)
  end

  def invert
    Ncurses.attron(Ncurses::A_REVERSE)
  end

  def write(x, y, string)
    Ncurses.mvaddstr(y, x, string)
  end

  def clear
    Ncurses.erase
  end

  def tick
    @things.each { |thing| thing.tick }
  end

  def draw
    @things.each { |thing| thing.draw }
    Ncurses.stdscr.noutrefresh
    Ncurses.doupdate
  end

end

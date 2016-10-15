#!/usr/bin/env ruby

require 'ncursesw'

module HasWindow

  def screen_width
    Ncurses.COLS
  end

  def screen_height
    Ncurses.LINES
  end

  def width
    screen_width
  end

  def height
    screen_height
  end
  
  def getch
    @window.getch
  end

  # Sets curses's attributes for writing
  # Takes in a color definition followed by attribute symbols
  # Color definition is 1, 3, or 4 ints; see color1, color3, and color4
  # Attribute symbols are :blink, :bold, :dim, :reverse, :standout, :underline
  def color(*args)
    (options ||= []) << args.pop while args.last.is_a?(Symbol)
    case args.size
    when 1
      color1(*args)
    when 3
      color3(*args)
    when 4
      color4(*args)
    end
    if options 
      blink if options.delete(:blink)
      bold if options.delete(:bold)
      dim if options.delete(:dim)
      reverse if options.delete(:reverse)
      standout if options.delete(:standout)
      underline if options.delete(:underline)
    end
  end

  def hsv_to_color(h, s, v)
    r = (h * 6.0 - 3.0).abs - 1.0
    g = 2.0 - (h * 6.0 - 2.0).abs
    b = 2.0 - (h * 6.0 - 4.0).abs
    [ r,g,b ].map do |f|
      f = [ 0.0, [ f, 1.0 ].min ].max
      f = ((f - 1.0) * s + 1.0) * v
      (f * 5.0).round
    end
  end

  def hsv(*args)
    rgb = hsv_to_color(*args[0...3])
    color(*(rgb + args[3..-1]))
  end

  # Sets color to the specified color pair id
  def color1(pair)
    @window.attrset(Ncurses.COLOR_PAIR(pair))
  end

  # Sets color to the specified 216-color color pair, where r,g,b are integers
  # in the range [0,6)
  def color3(r,g,b)
    @window.attrset(Ncurses.COLOR_PAIR(16 + 36*r + 6*g + b))
  end

  # Sets color to the specified 16-color color pair, where r,g,b,a are either 0
  # or 1
  def color4(r,g,b,i)
    @window.attrset(Ncurses.COLOR_PAIR(r + 2*g + 4*b + 8*i))
  end

  def blink
    @window.attron(Ncurses::A_BLINK)
  end

  def bold
    @window.attron(Ncurses::A_BOLD)
  end

  def dim
    @window.attron(Ncurses::A_DIM)
  end

  def reverse
    @window.attron(Ncurses::A_REVERSE)
  end

  def standout
    @window.attron(Ncurses::A_STANDOUT)
  end

  def underline
    @window.attron(Ncurses::A_UNDERLINE)
  end

  def write(x, y, string)
    @window.mvaddstr(y, x, string)
  end

  def touchline(y, h)
    Ncurses.touchline(@window, y, h)
  end

  def erase
    @window.erase
  end

end

module HasPad

  include HasWindow

  def pad
    self
  end

  def width
    @_HasPad__width
  end

  def height
    @_HasPad__height
  end

  def new_pad(width, height)
    @window = Ncurses.newpad(height, width)
    @_HasPad__width = width
    @_HasPad__height = height
  end

  def render_pad(src_x, src_y, dst_x, dst_y, dst_x2, dst_y2)
    @window.pnoutrefresh(src_y, src_x, dst_y, dst_x, dst_y2, dst_x2)
  end

end
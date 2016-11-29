#!/usr/bin/env ruby

# Interface objects with ncurses by including HasWindow or HasPad.

require 'ncursesw'

module HasWindow

  def screen_width
    Ncurses.COLS
  end

  def screen_height
    Ncurses.LINES
  end

  def getch
    # This gets a UTF-8 character from a stream of bytes
    first = @curses_window.getch
    return first if first == -1 or first == Ncurses::KEY_MOUSE
    if (first & 0b11111100) == 0b11111100
      count = 6
    elsif (first & 0b11111000) == 0b11111000
      count = 5
    elsif (first & 0b11110000) == 0b11110000
      count = 4
    elsif (first & 0b11100000) == 0b11100000
      count = 3
    elsif (first & 0b11000000) == 0b11000000
      count = 2
    elsif (first & 0b10000000) == 0b10000000
      return first
    else
      count = 1
    end
    bytes = [ first ]
    (count-1).times { bytes << @curses_window.getch }
    $logger.debug(bytes.to_s)
    return first if bytes.any? { |b| b == -1 }
    out = bytes.pack('C*').force_encoding('UTF-8').ord
    $logger.debug(out)
    out
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
    @curses_window.attrset(Ncurses.COLOR_PAIR(pair))
  end

  # Sets color to the specified 216-color color pair, where r,g,b are integers
  # in the range [0,6)
  def color3(r,g,b)
    @curses_window.attrset(Ncurses.COLOR_PAIR(16 + 36*r + 6*g + b))
  end

  # Sets color to the specified 16-color color pair, where r,g,b,a are either 0
  # or 1
  def color4(r,g,b,i)
    @curses_window.attrset(Ncurses.COLOR_PAIR(r + 2*g + 4*b + 8*i))
  end

  def blink
    @curses_window.attron(Ncurses::A_BLINK)
  end

  def bold
    @curses_window.attron(Ncurses::A_BOLD)
  end

  def dim
    @curses_window.attron(Ncurses::A_DIM)
  end

  def reverse
    @curses_window.attron(Ncurses::A_REVERSE)
  end

  def standout
    @curses_window.attron(Ncurses::A_STANDOUT)
  end

  def underline
    @curses_window.attron(Ncurses::A_UNDERLINE)
  end

  def write(x, y, string)
    @curses_window.mvaddstr(y, x, string)
  end

  def erase
    @curses_window.erase
  end

end

module HasPad

  include HasWindow

  def pad
    self
  end

  def pad_width
    @pad_width
  end

  def pad_height
    @pad_height
  end

  def new_pad(*args)
    if args.length == 1
      width = args[0].x
      height = args[0].y
    elsif args.length == 2
      width = args[0]
      height = args[1]
    end

    pad = Ncurses.newpad(height, width)
    raise "Failed to create a pad! width=#{width} height=#{height}" if pad == nil

    @curses_window = pad
    @pad_width = width
    @pad_height = height
  end

  def render_pad(src_x, src_y, dst_x, dst_y, dst_x2, dst_y2)
    @curses_window.pnoutrefresh(src_y, src_x, dst_y, dst_x, dst_y2, dst_x2)
  end

end

module PadHelpers

  def rerender_pad(clip = self.clip, size = self.size, origin = self.origin)
    return unless size.x > 0 && size.y > 0
    gpos = global_pos
    render_pad(origin.x+clip.x, origin.y+clip.y, gpos.x+clip.x, gpos.y+clip.y, gpos.x+clip.x+size.x-1, gpos.y+clip.y+size.y-1)
  end

end

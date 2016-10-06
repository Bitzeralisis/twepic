require 'ncursesw'

module HasWindow

  def width
    Ncurses.COLS
  end

  def height
    Ncurses.LINES
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

  # Sets color to the specified color pair id
  def color1(pair)
    @window.attrset(Ncurses.COLOR_PAIR(pair))
  end

  # Sets color to the specified 216-color color pair, where r,g,b are integers
  # in the range [0,6]
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

  def erase
    @window.erase
  end

  def quit
    @quit = true
  end

end

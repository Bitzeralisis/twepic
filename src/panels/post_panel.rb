require_relative 'panel'
require_relative '../config'
require_relative '../world/window'

class PostPanel < Panel

  include HasPad
  include PadHelpers

  def initialize
    super
    self.size = screen_width, 6
    self.visible = false
    @post = ''
    @reply_to = nil
    @time = 0
  end

  def set_target(post:, reply_to:)
    @post = post
    @reply_to = reply_to
  end

  def tick(time)
    flag_redraw if size.y > 0
    @time += time
  end

  def consume_input(input, config)
    case input

      when Ncurses::KEY_MOUSE
        nil

      # Ctrl-w
      when 23
        # Delete a word
        index = @post.rindex(/\b\w+/)
        @post = @post[0...index] if index

      # Esc
      when 27
        # Exit post mode
        @post = ''
        @parent.switch_mode(:previous_mode)

      # Backspace
      when 127
        # Delete a character
        @post = @post[0..-2]

      # Return
      when "\r".ord
        # If there's a backslash at the end, remove the backslash and insert a newline
        if @post[-1] == "\\"
          @post[-1] = "\n"
        else
          # Else post the tweet
          @parent.post_tweet(post: @post, reply_to: @reply_to)
          @post = ''
          @parent.switch_mode(:previous_mode)
        end

      when Ncurses::KEY_MOUSE
        mouse_event = Ncurses::MEVENT.new
        Ncurses::getmouse(mouse_event)
        # @post += mouse_event.bstate.to_s + ' '

      else
        # Every other input is just a character in the post
        @post += input.chr(Encoding::UTF_8)
    end

    true
  end

  def redraw
    pad.erase

    # Render status bar
    r,g,b = @reply_to ? [5,4,2] : [2,4,5]
    glow = 0.75 + 0.25*Math.sin(@time/20.0)
    gr,gg,gb = [r,g,b].map { |f| (f*glow).round }

    pad.color(gr,gg,gb, :reverse)
    pad.write(0, 3, ''.ljust(size.x))

    # TODO More correct update length checking based on shortened URL, etc.
    tweet_length = @post.length
    tweet_length_display = ' ' + tweet_length.to_s + ' / 140 '
    display_width = UnicodeUtils.display_width(tweet_length_display)
    if tweet_length > 140
      pad.color(5,0,0, :reverse)
    else
      pad.color(r,g,b, :reverse)
    end
    pad.write(size.x-display_width-1, 3, tweet_length_display)

    if @reply_to
      pad.color(r,g,b, :bold)
      pad.write((size.x-7)/2, 3, ' v v v ')
    end

    pad.color(r,g,b, :bold, :reverse)
    pad.write(ColumnDefinitions::COLUMNS[:UsernameColumn]-1, 3, @reply_to ? ' COMPOSE REPLY ' : ' COMPOSE UPDATE ')

    # Render the post
    display = "#{@post.gsub("\n", '↵ ')}␣"
    pad.color(1,1,1,1)
    pad.write(ColumnDefinitions::COLUMNS[:UsernameColumn], 5, display)
    pad.bold
    pad.write(ColumnDefinitions::COLUMNS[:SelectionColumn], 5, '  >')
  end

  def rerender
    rerender_pad(Coord.new(0, 2), Coord.new(size.x, size.y-2))
  end

  def on_resize(old_size, new_size)
    return if old_size == new_size
    new_pad(new_size)
    flag_redraw
  end

end

class ConfirmPanel < Panel

  include HasPad
  include PadHelpers

  def initialize
    super
    self.size = screen_width, 4
    self.visible = false
    @time = 0
  end

  def set_action(action_type:, action_text:, confirm_keys:, deny_keys:)
    @action_type = action_type
    @action_text = action_text
    @confirm_keys = confirm_keys
    @deny_keys = deny_keys
  end

  def tick(time)
    flag_redraw(size.y > 0)
    @time += time
  end

  def consume_input(input, config)
    if @confirm_keys.include?(input)
      case @action_type
        when :retweet
          @parent.clients.rest_concurrently(:retweet, @parent.selected_tweet.tweet.id) { |rest, id| rest.retweet(id) }
          @parent.switch_mode(:previous_mode)
        when :delete
          @parent.clients.rest_concurrently(:delete, @parent.selected_tweet.tweet.id) { |rest, id| rest.destroy_status(id) }
          @parent.switch_mode(:previous_mode)
      end
    elsif @deny_keys.include?(input)
      @parent.switch_mode(:previous_mode)
    end

    true
  end

  def redraw
    pad.erase

    r,g,b =
        case @action_type
          when :retweet
            [0,5,0]
          when :delete
            [5,0,0]
        end
    glow = 0.5 + 0.5*Math.sin(@time/20.0)
    gr,gg,gb = [r,g,b].map { |f| (f*glow).round }

    pad.color(r,g,b, :bold)
    pad.write((size.x-5)/2, 1, 'v v v')

    pad.color(gr,gg,gb, :reverse)
    pad.write(0, 3, ''.ljust(size.x))

    pad.color(r,g,b, :bold, :reverse)
    pad.write(ColumnDefinitions::COLUMNS[:UsernameColumn]-1, 3, " #{@action_text} ")
  end

  def rerender
    rerender_pad(Coord.new(0, 1), Coord.new(size.x, size.y-1))
  end

  def on_resize(old_size, new_size)
    return if old_size == new_size
    new_pad(new_size)
    flag_redraw
  end

end


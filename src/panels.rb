#!/usr/bin/env ruby

require 'twitter'
require 'twitter-text'
require 'unicode_utils'
require_relative 'tweetline'
require_relative 'world'

class TweetsPanel < Thing

  attr_reader :clients
  attr_reader :time
  attr_reader :world

  START_Y = 4
  END_Y = -11
  def height
    @_height ||= @world.height - START_Y + END_Y
  end
  SELECTION_START_Y = -10
  POST_START_Y = -6
  CONFIRM_START_Y = -6

  def initialize(clients)
    @clients = clients

    @mode = :timeline

    @tweetstore = TweetStore.new

    @prev_top = -1
    @next_top = 0
    @selected = 0
    @prev_selected = 0

    @header = ''

    @post = ''
    @reply_to = nil

    @confirm_action = nil
    @confirm_keys = [ ]
    @deny_keys = [ ]
    @confirm_text = ''

    @redraw = true
    @time = 0
  end

  def tick
    # Consume events from streaming
    until @clients.stream_queue.empty?
      event = @clients.stream_queue.pop
      case event
      when Twitter::Tweet
        # If the selection arrow is on the streaming spinner, then follow it
        @selected += 1 if @selected == @tweetstore.size
        # If we can scroll down one tweet without the selection arrow
        # disappearing, then do so, but only if the view is full
        @next_top += 1 if @selected > @next_top &&
          @next_top + @world.height - START_Y + END_Y - 1 == @tweetstore.size
        @tweetstore << TweetLine.new(self, @tweetstore, event, @time)

      when Twitter::Streaming::DeletedTweet
        @tweetstore.delete_id(event.id)
        select_tweet(@selected)
        @redraw = true

      end
    end

    # Consume inputs
    while true
      input = @world.getch
      break if input == -1
      case @mode
      when :timeline
        timeline_consume_input(input)
      when :post
        post_consume_input(input)
      when :confirm
        confirm_consume_input(input)
      end
    end

    # Tick just tweetlines that are visible
    @tweetstore[@next_top, height].each { |t| t.tick_to(@time) }

    @time += 1
  end

  def draw
    render_timeline
    render_selection
    render_post
    render_confirm
    render_statusline
    @redraw = false
  end

  def do_noutrefresh
    # Copy tweetlines that are visible to the screen
    i = START_Y
    @tweetstore[@next_top, height].each_index do |index|
      index += @next_top
      tweet = @tweetstore[index]
      tweet.do_noutrefresh(i)
      i += 1
    end
  end

  def timeline_consume_input(input)
    if @header == 'z'
      case input
        when 't'.ord
          scroll_top(@selected)
        when 'z'.ord
          scroll_top(@selected-(height-1)/2)
        when 'b'.ord
          scroll_top(@selected-height+1)
      end
      @header = ''
    else
      case input
      # Mouse control

      when Ncurses::KEY_MOUSE
        mouse_event = Ncurses::MEVENT.new
        Ncurses::getmouse(mouse_event)
        if mouse_event.bstate & Ncurses::BUTTON1_PRESSED != 0
          select_tweet(@next_top + mouse_event.y-START_Y) if mouse_event.y >= START_Y and mouse_event.y < @world.height+END_Y
        elsif mouse_event.bstate & Ncurses::BUTTON4_PRESSED != 0
          scroll_top([ 0, @next_top-1 ].max)
        elsif mouse_event.bstate & Ncurses::BUTTON2_PRESSED != 0 # or mouse_event.bstate & Ncurses::REPORT_MOUSE_POSITION != 0
          scroll_top([ @next_top+1, @tweetstore.size ].min)
        end

      # Keyboard control

      # Movement commands
      when 'k'.ord, 259 # up arrow
        select_tweet([ 0, @selected-1 ].max)
      when 'j'.ord, 258 # down arrow
        select_tweet([ @selected+1, @tweetstore.size ].min)
      when 'f'.ord
        select_tweet([ @selected+height, @tweetstore.size ].min)
      when 'b'.ord
        select_tweet([ 0, @selected-height ].max)

      when 'H'.ord
        select_tweet(@next_top)
      when 'M'.ord
        select_tweet([ @next_top+(height-1)/2, @tweetstore.size ].min)
      when 'L'.ord
        select_tweet([ @next_top+height-1, @tweetstore.size ].min)
      when 'G'.ord
        select_tweet(@tweetstore.size)

      when 'h'.ord, 'l'.ord, 260, 261 # left arrow, right arrow
        if @tweetstore.reply_tree.size > 1
          rt_index = @tweetstore.reply_tree.find_index { |tl| tl.tweet.id >= @tweetstore[@selected].tweet.id }
          rt_index = [ 0, rt_index-1 ].max if [ 'h'.ord, 260  ].include?(input)
          rt_index = [ rt_index+1, @tweetstore.reply_tree.size-1 ].min if [ 'l'.ord, 261 ].include?(input)
          ts_index = @tweetstore.find_index { |tl| tl.tweet.id == @tweetstore.reply_tree[rt_index].tweet.id }
          select_tweet(ts_index, false) if ts_index
        end

      # Viewport commands
      when 'z'.ord
        @header = 'z'

      # Switch to post-mode commands
      when 't'.ord
        @mode = :post
        @reply_to = nil

      when 'r'.ord, 'R'.ord
        return unless @tweetstore[@selected] # Do nothing when following stream
        @mode = :post

        # When replying to a retweet, we reply to the retweeted status, not the status that is a retweet
        reply_tweetline = @tweetstore[@selected]
        @reply_to =
          if reply_tweetline.retweet?
            reply_tweetline.tweet.retweeted_status
          else
            reply_tweetline.tweet
          end

        # Populate the tweet with the @names of people being replied to
        if input == 'R'.ord # Also include @names of every person mentioned in the tweet
          mentioned_users = Twitter::Extractor::extract_mentioned_screen_names(@reply_to.text)
          mentioned_users = mentioned_users.uniq
          mentioned_users.delete(@reply_to.user.screen_name)
          mentioned_users.unshift(@reply_to.user.screen_name)
          mentioned_users.delete(@clients.user.screen_name)
          mentioned_users << reply_tweetline.tweet.user.screen_name if reply_tweetline.retweet?
          mentioned_users.map! { |u| "@#{u}" }
          @post = "#{mentioned_users.join(' ')} "
        elsif input == 'r'.ord # Only have @name of the user of the tweet
          @post = "@#{@reply_to.user.screen_name} "
        end

      # Switch to confirm-mode commands
      when 'e'.ord
        return unless @tweetstore[@selected] # Do nothing when following stream
        @mode = :confirm
        @confirm_action = :retweet
        @confirm_keys = [ 'y'.ord, 'Y'.ord, 'e'.ord, '\r'.ord ]
        @deny_keys = [ 'n'.ord, 'N'.ord, 27 ] # Esc
        @confirm_text = "Really retweet this tweet? eyY/nN"

      when 'd'.ord
        return unless @tweetstore[@selected] # Do nothing when following stream
        @mode = :confirm
        @confirm_action = :delete
        @confirm_keys = [ 'y'.ord, 'Y'.ord, 'd'.ord, '\r'.ord ]
        @deny_keys = [ 'n'.ord, 'N'.ord, 27 ] # Esc
        @confirm_text = "Really delete this tweet? dyY/nN"

      # Other commands
      when 'Q'.ord
        @world.quit

      end
    end
  end

  def render_timeline
    return if @tweetstore.size == 0

    # Figure out which index is the topmost tweet to display
    num_tweets = @tweetstore.size
    height = @world.height - START_Y + END_Y
    bottom = @world.height + END_Y
    top = @next_top

    # If top changed, then every tweet needs to be re-rendered
    @redraw = true if @prev_top != top

    # Draw the top bar
    if @redraw
      @world.erase
      @prev_top = top
      @next_top = top

      @world.color4(0,1,1,0)
      @world.reverse
      @world.bold
      @world.write(3, 1, ' TIMELINE ')

      @world.color(0,1,1,1, :bold, :reverse)
      @world.write(0, 2, ''.ljust(@world.width))
      @world.write(TweetLine::USERNAME_X+1, 2, 'USER')
      @world.write(TweetLine::TWEET_X, 2, 'TWEET')
    end

    # Draw tweets to their pads
    i = START_Y
    @tweetstore[top, height].each_index do |index|
      index += top
      tweet = @tweetstore[index]
      tweet.render(selected: index == @selected)
      i += 1
    end

    # Draw the "streaming" spinner
    if i < bottom
      @world.color(0,0,0,1)
      @world.write(TweetLine::SELECTION_X, i, ' ') # Clear the selection arrow
      @world.write(TweetLine::TWEET_X, i, 'Streaming...')
      @world.write(TweetLine::TWEET_X+13, i, ['–','\\','|','/'][(@time/3)%4])
    end

    # Draw selection arrow
    @world.color(0)
    (START_Y...bottom).each do |y|
      @world.write(TweetLine::SELECTION_X, y, ' ')
    end
    @world.color(1,1,1,1, :bold)
    @world.write(0, @selected-top+START_Y, '> '.rjust(TweetLine::SELECTION_X+2))

    # Draw relational arrows into tweetlines' pads
    @tweetstore[top, height].each do |tl|
      tl.color(0)
      tl.write(TweetLine::RELATIONS_X, 0, ' ')
    end

    if @tweetstore[@selected]
      @tweetstore[top, height].each do |tl|
        # Tweet by same user
        if tl.tweet.user.id == @tweetstore[@selected].tweet.user.id
          tl.color(4,4,1, :bold)
          tl.write(TweetLine::RELATIONS_X-1, 0, ' > ')
        end

        # Tweet in replied-to chain (highlight the most immediate replied-to)
        if @tweetstore.reply_tree.size > 1 and @tweetstore.reply_tree.include?(tl)
          if tl.tweet.user.id == @tweetstore[@selected].tweet.user.id
            tl.color(4,4,1, :bold, :reverse)
          else
            tl.color(5,3,3, :bold, :reverse)
          end
          tl.write(TweetLine::RELATIONS_X, 0, '>');
        end
      end
    end

    # Draw scrollbar
    @world.color4(0,0,0,1)
    (START_Y...bottom).each { |y| @world.write(@world.width-2, y, '|') }

    top_end = ((height-1) * (top.to_f / @tweetstore.size)).floor + START_Y
    bottom_end = ((height-1) * [ (top+height).to_f / @tweetstore.size, 1.0 ].min).ceil + START_Y
    @world.color4(1,1,1,1)
    @world.bold
    @world.write(@world.width-2, top_end, 'o')
    (top_end+1..bottom_end-1).each { |y| @world.write(@world.width-2, y, '|') }
    @world.write(@world.width-2, bottom_end, 'o')
  end

  def render_selection
    return unless @redraw or @prev_selected != @selected

    @prev_selected = @selected

    y = @world.height + SELECTION_START_Y

    # Clear the selection area
    @world.color(0)
    @world.write(0, y, ''.ljust(4 * @world.width))
    @world.write(0, y+2, ''.ljust(2 * @world.width))

    return unless @tweetstore[@selected]
    tweetline = @tweetstore[@selected]

    username =
      if tweetline.retweet?
        "@#{tweetline.tweet.retweeted_status.user.screen_name} << @#{tweetline.tweet.user.screen_name}"
      else
        "@#{tweetline.tweet.user.screen_name}"
      end

    tweet_body =
      if tweetline.retweet?
        tweetline.tweet.retweeted_status.text
      else
        tweetline.tweet.text
      end
    tweet_body = tweet_body.gsub(/[\r\n\t]/, '  ')
    tweet_body = $htmlentities.decode(tweet_body)

    time = tweetline.tweet.created_at.getlocal.strftime "%Y-%m-%d %H:%M:%S"

    @world.color4(1,1,1,1)
    @world.bold
    @world.reverse
    @world.write(0, y, ''.ljust(@world.width))
    @world.write(TweetLine::USERNAME_X, y, username)

    @world.color4(1,1,1,1)
    @world.reverse
    @world.write(@world.width-time.length-1, y, time)

    @world.color4(1,1,1,1)
    @world.write(TweetLine::USERNAME_X, y+2, tweet_body)
  end

  def post_consume_input(input)
    case input

    # Esc
    when 27
      # Exit post mode
      @post = ''
      @mode = :timeline

    # Backspace
    when 127
      # Delete a character
      @post = @post[0..-2]

    # Return
    when "\r".ord
      # Post the tweet
      post_tweet
      @post = ''
      @mode = :timeline

    when Ncurses::KEY_MOUSE
      mouse_event = Ncurses::MEVENT.new
      Ncurses::getmouse(mouse_event)
      @post += mouse_event.bstate.to_s + ' '

    else
      # Every other input is just a character in the post
      @post += input.chr(Encoding::UTF_8)
      #@post += input.to_s
    end
  end

  def render_post
    y = @world.height + POST_START_Y

    # Clear the post area
    @world.color(0)
    @world.write(0, y, ''.ljust(@world.width))
    @world.write(0, y+2, ''.ljust(@world.width))
    @world.write(0, y+4, ''.ljust(2 * @world.width))

    if @mode == :post
      # Render status bar
      r,g,b = @reply_to ? [5,4,2] : [2,4,5]
      glow = 0.75 + 0.25*Math.sin(@time/20.0)
      gr,gg,gb = [r,g,b].map { |f| (f*glow).round }

      @world.color3(gr,gg,gb)
      @world.reverse
      @world.write(0, y+2, ''.ljust(@world.width))

      # TODO More correct update length checking based on shortened URL, etc.
      tweet_length = @post.length
      tweet_length_display = ' ' + tweet_length.to_s + ' / 140 '
      display_width = UnicodeUtils.display_width(tweet_length_display)
      if tweet_length > 140
        @world.color3(5,0,0)
        @world.reverse
      else
        @world.color3(r,g,b)
        @world.reverse
      end
      @world.write(@world.width-display_width-1, y+2, tweet_length_display)

      if @reply_to
        @world.color3(gr,gg,gb)
        @world.bold
        @world.write((@world.width-5)/2, y, 'v v v')
      end

      @world.color3(r,g,b)
      @world.reverse
      @world.bold
      @world.write(TweetLine::USERNAME_X-1, y+2, @reply_to ? ' COMPOSE REPLY ' : ' COMPOSE UPDATE ')

      # Render the post
      @world.color4(1,1,1,1)
      @world.write(TweetLine::USERNAME_X, y+4, @post)
      @world.bold
      @world.write(TweetLine::SELECTION_X, y+4, '>')
    end
  end

  def post_tweet
    # The first at-mention in the tweet must match the user being replied to,
    # otherwise don't count it as a reply
    # TODO Make it check the first at-mention, not just any at-mention
    # TODO Make it not care if you're replying to yourself
    if @reply_to and @reply_to.user != @clients.user and !@post.include?("@#{@reply_to.user.screen_name}")
      @reply_to = nil
    end

    if @reply_to
      @clients.rest_api.update(@post, in_reply_to_status: @reply_to)
    else
      @clients.rest_api.update(@post)
    end
  end

  def confirm_consume_input(input)
    if @confirm_keys.include?(input)
      case @confirm_action
      when :retweet
        @clients.rest_api.retweet(@tweetstore[@selected].tweet.id)
        @mode = :timeline
      when :delete
        @clients.rest_api.destroy_status(@tweetstore[@selected].tweet.id)
        @mode = :timeline
      end
    elsif @deny_keys.include?(input)
      @mode = :timeline
    end
  end

  def render_confirm
    return unless @mode == :confirm

    y = @world.height + CONFIRM_START_Y

    # Clear the area
    @world.color(0)
    @world.write(0, y, ''.ljust(@world.width))
    @world.write(0, y+2, ''.ljust(@world.width))
    
    r,g,b =
      case @confirm_action
      when :retweet
        [0,5,0]
      when :delete
        [5,0,0]
      end
    glow = 0.5 + 0.5*Math.sin(@time/20.0)
    gr,gg,gb = [r,g,b].map { |f| (f*glow).round }

    @world.color3(gr,gg,gb)
    @world.bold
    @world.write((@world.width-5)/2, y, 'v v v')

    @world.color3(gr,gg,gb)
    @world.reverse
    @world.write(0, y+2, ''.ljust(@world.width))

    @world.color3(r,g,b)
    @world.reverse
    @world.bold
    @world.write(TweetLine::USERNAME_X-1, y+2, " #{@confirm_text} ")
  end

  def render_statusline
    @world.color4(1,1,1,1)
    @world.write(@world.width-1, @world.height-1, @header.ljust(1))
  end

  private

  def select_tweet(index, rebuild = true)
    @selected = [ 0, [ index, @tweetstore.size ].min ].max
    if @selected < @next_top
      @next_top = @selected
    elsif @selected >= @next_top + height
      @next_top = @selected - height + 1
    end
    @tweetstore.rebuild_reply_tree(@tweetstore[@selected]) if @tweetstore[@selected] and rebuild
  end

  def scroll_top(index)
    @next_top = [ 0, [ index, @tweetstore.size ].min ].max
    if @selected >= @next_top + height
      @selected = @next_top + height - 1
    elsif @selected < @next_top
      @selected = @next_top
    end
  end

end

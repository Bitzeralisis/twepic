#!/usr/bin/env ruby

require 'twitter'
require 'twitter-text'
require 'unicode_utils'
require_relative 'tweetline'
require_relative 'tweetstore'
require_relative 'world/world'

class PanelSet < ThingContainer

  include HasWindow

  attr_reader :clients
  attr_reader :config
  attr_reader :time
  attr_reader :tweetstore
  attr_reader :world

  def initialize(clients, config)
    super()

    @clients = clients
    @config = config

    @mode = :timeline

    @tweetstore = TweetStore.new(config, clients)
    @tweetstore.check_profile_image(@clients.user)

    @statusline = ''
    @header = ''

    @post = ''
    @reply_to = nil

    @confirm_action = nil
    @confirm_keys = [ ]
    @deny_keys = [ ]
    @confirm_text = ''

    @time = 0

    @title_panel = TitlePanel.new(@clients)
    @tweets_panel = TweetsPanel.new(@tweetstore)
    @detail_panel = DetailPanel.new(@config, @tweetstore)
    @post_panel = PostPanel.new
    @confirm_panel = ConfirmPanel.new

    self << @title_panel
    self << @tweets_panel
    self << @detail_panel
    self << @post_panel
    self << @confirm_panel
  end

  def selected_tweet
    @tweets_panel.selected_tweet
  end

  def selected_index
    @tweets_panel.selected_index
  end

  def visible_tweets
    @tweets_panel.visible_tweets
  end

  def top
    @tweets_panel.top
  end

  def tweetview
    @tweets_panel.tweetview
  end

  def tick(time)
    @time += time

    # Consume events from streaming
    until @clients.stream_queue.empty?
      event = @clients.stream_queue.pop
      case event
        when Twitter::Tweet
          # TODO: Deal with duplicates
          # TODO: When it's a retweet of your own tweet, carry over fav and rt count from orig tweet
          # TODO: When it's a retweet of your own tweet, increment your tweet's rt count
          #       and the rt count of every rt of that tweet.
          # If we can scroll down one tweet without the selection arrow
          # disappearing, then do so, but only if the view is full
          scroll_top(top+1) if selected_index > top && top + @tweets_panel.size.y - 1 == @tweetstore.size
          @tweetstore << TweetLine.new(@tweets_panel, @tweetstore, event, @time)
          # If the selection arrow was on the streaming spinner, then follow it
          select_tweet(selected_index+1) if selected_index == @tweetstore.size-1

        when Twitter::Streaming::DeletedTweet
          @tweetstore.delete_id(event.id)
          # TODO: Instead of just shifting everything up, attempt to keep @selected on the same
          #       tweet if possible
          select_tweet(selected_index)

        when Twitter::Streaming::Event
          case event.name
            when :access_revoked
              nil
            when :block, :unblock
              nil
            when :favorite, :unfavorite
              # TODO: Also change favorited/favorites of all rts of that tweet
              tweetline = @tweetstore.fetch(event.target_object.id)
              if tweetline
                if event.target_object.user.id == @clients.user.id
                  tweetline.favorites += 1 if event.name == :favorite
                  tweetline.favorites -= 1 if event.name == :unfavorite
                else
                  tweetline.favorited = true if event.name == :favorite
                  tweetline.favorited = false if event.name == :unfavorite
                end
              end
            when :follow, :unfollow
              nil
            when :quoted_tweet
              nil
            when :user_update
              nil
            else
              # Not included: all the list events
              nil
          end
      end
    end

    # Consume inputs
    while true
      input = world.getch
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

    # Tick panels
    @detail_panel.tweetline = selected_tweet
    @post_panel.set_target(@post, @reply_to)
    @confirm_panel.set_action(@confirm_action, @confirm_text)

    self.size = screen_width, screen_height

    super
  end

  def timeline_consume_input(input)
    if @header == 'z'
      case input
        when 't'.ord
          scroll_top(selected_index)
        when 'z'.ord
          scroll_top(selected_index-(@tweets_panel.size.y-1)/2)
        when 'b'.ord
          scroll_top(selected_index-@tweets_panel.size.y+1)
      end
      @header = ''
    else
      case input
        # Mouse control

        when Ncurses::KEY_MOUSE
          mouse_event = Ncurses::MEVENT.new
          Ncurses::getmouse(mouse_event)
          if mouse_event.bstate & Ncurses::BUTTON1_PRESSED != 0
            select_tweet(top + mouse_event.y-@tweets_panel.pos.y) if mouse_event.y >= @tweets_panel.pos.y && mouse_event.y < @tweets_panel.size.y+@tweets_panel.pos.y
          elsif mouse_event.bstate & Ncurses::BUTTON4_PRESSED != 0
            scroll_top(top-3)
          elsif mouse_event.bstate & Ncurses::BUTTON2_PRESSED != 0 # or mouse_event.bstate & Ncurses::REPORT_MOUSE_POSITION != 0
            scroll_top(top+3)
          end

        # Keyboard control

        # Movement commands
        when 'k'.ord, 259 # up arrow
          select_tweet(selected_index-1)
        when 'j'.ord, 258 # down arrow
          select_tweet(selected_index+1)

        when 'H'.ord
          select_tweet(top)
        when 'M'.ord
          select_tweet(top+(visible_tweets.size-1)/2)
        when 'L'.ord
          select_tweet(top+visible_tweets.size-1)
        when 'g'.ord
          select_tweet(0)
        when 'G'.ord
          select_tweet(tweetview.size-1)

        # TODO: Traverse all relations with this, not just the reply tree
        when 'h'.ord, 'l'.ord, 260, 261 # left arrow, right arrow
          if @tweetstore.reply_tree.size > 1 and selected_tweet.is_tweet?
            rt_index = @tweetstore.reply_tree.find_index { |tl| tl.tweet.id >= selected_tweet.tweet.id }
            rt_index = [ 0, rt_index-1 ].max if [ 'h'.ord, 260  ].include?(input)
            rt_index = [ rt_index+1, @tweetstore.reply_tree.size-1 ].min if [ 'l'.ord, 261 ].include?(input)
            ts_index = @tweetstore.find_index { |tl| tl.tweet.id == @tweetstore.reply_tree[rt_index].tweet.id }
            select_tweet(ts_index, false) if ts_index
          end

        # Scrolling commands
        when 'z'.ord
          @header = 'z'

        # No confirmation commands
        when 'f'.ord
          # TODO: Favorite retweets correctly
          return unless selected_tweet.is_tweet?
          @clients.rest_api.favorite(selected_tweet.tweet.id)
        when 'F'.ord
          # TODO: Don't crash when the tweet is un-unfavoritable
          return unless selected_tweet.is_tweet?
          @clients.rest_api.unfavorite(selected_tweet.tweet.id)

        # Switch to post-mode commands
        when 't'.ord
          switch_mode(:post)
          @reply_to = nil

        when 'r'.ord, 'R'.ord
          return unless selected_tweet.is_tweet? # Do nothing when following stream
          switch_mode(:post)

          # When replying to a retweet, we reply to the retweeted status, not the status that is a retweet
          reply_tweetline = selected_tweet
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
          return unless selected_tweet.is_tweet? # Do nothing when following stream
          switch_mode(:confirm)
          @confirm_action = :retweet
          @confirm_keys = [ 'y'.ord, 'Y'.ord, 'e'.ord, '\r'.ord ]
          @deny_keys = [ 'n'.ord, 'N'.ord, 27 ] # Esc
          @confirm_text = 'Really retweet this tweet? eyY/nN'

        when 'd'.ord
          return unless selected_tweet.is_tweet? # Do nothing when following stream
          return unless selected_tweet.tweet.user.id == @clients.user.id # Must be own tweet
          switch_mode(:confirm)
          @confirm_action = :delete
          @confirm_keys = [ 'y'.ord, 'Y'.ord, 'd'.ord, '\r'.ord ]
          @deny_keys = [ 'n'.ord, 'N'.ord, 27 ] # Esc
          @confirm_text = 'Really delete this tweet? dyY/nN'

        # Other commands
        when 'Q'.ord
          world.quit

      end
    end
  end

  def post_consume_input(input)
    case input

      when Ncurses::KEY_MOUSE
        nil

      # Esc
      when 27
        # Exit post mode
        @post = ''
        switch_mode(:timeline)

      # Backspace
      when 127
        # Delete a character
        @post = @post[0..-2]

      # Return
      when "\r".ord
        # Post the tweet
        post_tweet
        @post = ''
        switch_mode(:timeline)

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

  def confirm_consume_input(input)
    if @confirm_keys.include?(input)
      case @confirm_action
        when :retweet
          @clients.rest_api.retweet(selected_tweet.tweet.id)
          switch_mode(:timeline)
        when :delete
          @clients.rest_api.destroy_status(selected_tweet.tweet.id)
          switch_mode(:timeline)
      end
    elsif @deny_keys.include?(input)
      switch_mode(:timeline)
    end
  end

  def render
    super
    world.rerender
  end

  private

  def switch_mode(mode)
    @mode = mode
    case mode
      when :timeline
        @post_panel.visible = false
        @confirm_panel.visible = false
        @detail_panel.flag_rerender
      when :post
        @post_panel.visible = true
      when :confirm
        @confirm_panel.visible = true
    end
  end

  def select_tweet(index, rebuild = true)
    @tweets_panel.select_tweet(index, rebuild)
  end

  def scroll_top(index)
    @tweets_panel.scroll_top(index)
  end

  def post_tweet
    # The first at-mention in the tweet must match the user being replied to,
    # otherwise don't count it as a reply
    # TODO Make it check the first at-mention, not just any at-mention
    if @reply_to and @reply_to.user != @clients.user and !@post.include?("@#{@reply_to.user.screen_name}")
      @reply_to = nil
    end

    if @reply_to
      @clients.rest_api.update(@post, in_reply_to_status: @reply_to)
    else
      @clients.rest_api.update(@post)
    end
  end

  def on_resize(old_size, new_size)
    return if old_size == new_size
    @title_panel.pos = 0,0
    @tweets_panel.pos = 0,4
    @detail_panel.pos = 0, new_size.y-10
    @post_panel.pos = 0, new_size.y-7
    @confirm_panel.pos = 0, new_size.y-5
    @title_panel.size = new_size.x, @title_panel.size.y
    @tweets_panel.size = new_size.x, new_size.y-15
    @detail_panel.size = new_size.x, @detail_panel.size.y
    @post_panel.size = new_size.x, @post_panel.size.y
    @confirm_panel.size = new_size.x, @confirm_panel.size.y
    #@world.flag_rerender
  end

end

class TweetsPanel < Thing

  include HasPad
  include PadHelpers

  def initialize(tweetstore)
    super()
    self.size = screen_width, screen_height-15

    @tweetstore = tweetstore
    @tweetview = @tweetstore.create_view(self)

    @prev_top = -1
    @next_top = 0
    @prev_selected_vl = nil
    @selected = 0
    @prev_visible_tweets = []
    @prev_last_visible_y = -1

    @time = 0
  end

  def selected_tweet
    @tweetview[@selected]
  end

  def selected_index
    @selected
  end

  def visible_tweets
    @tweetview[@next_top, size.y]
  end

  def top
    @next_top
  end

  def tweetview
    @tweetview
  end

  def select_tweet(index, rebuild = true)
    @selected = [ 0, [ index, @tweetview.size-1 ].min ].max
    if @selected < @next_top
      scroll_top(@selected)
    elsif @selected >= @next_top + size.y
      scroll_top(@selected - size.y + 1)
    end
    @tweetstore.rebuild_reply_tree(selected_tweet) if selected_tweet.is_tweet? and rebuild
  end

  def scroll_top(index)
    @next_top = [ 0, [ index, @tweetview.size-1 ].min ].max
    if @selected >= @next_top + size.y
      select_tweet(@next_top + size.y - 1)
    elsif @selected < @next_top
      select_tweet(@next_top)
    end
  end

  def tick(time)
    # Set selected tweetlines
    if @prev_selected_vl != selected_tweet
      @prev_selected_vl.select(false) if @prev_selected_vl
      selected_tweet.select
    end

    # Set relations on tweetlines
    visible_tweets.each do |tl|
      if tl.is_tweet?
        tl.set_relations

        if selected_tweet.is_tweet?
          # Tweet by same user
          if tl.tweet.user.id == selected_tweet.tweet.user.id
            tl.set_relations(:same_user)
          end

          # Tweet in replied-to chain (highlight the most immediate replied-to)
          if @tweetstore.reply_tree.size > 1 and @tweetstore.reply_tree.include?(tl)
            if tl.tweet.user.id == selected_tweet.tweet.user.id
              tl.set_relations(:reply_tree_same_user)
            else
              tl.set_relations(:reply_tree_other_user)
            end
          end
        end
      end
    end

    # Tick and position the tweetlines that are visible
    visible_tweets.each.with_index do |tl, i|
      tl.pos.y = i
      tl.size = size.x-3, tl.size.y
      tl.tick_to(@time, time)
    end

    flag_redraw if @prev_top != @next_top

    @prev_top = @next_top
    @prev_selected_vl = selected_tweet

    @time += time
  end

  def draw
    super
    visible_tweets.each { |tl| tl.draw }
  end

  def redraw
    pad.erase

    # Draw scrollbar
    return if @tweetview.size == 0

    pad.color(0,0,0,1)
    (0...size.y).each { |y| pad.write(size.x-2, y, '|') }

    top_end = ((size.y-1) * (@next_top.to_f / @tweetview.size)).floor
    bottom_end = ((size.y-1) * [ (@next_top+size.y).to_f / @tweetview.size, 1.0 ].min).ceil
    pad.color(1,1,1,1)
    pad.bold
    pad.write(size.x-2, top_end, 'o')
    (top_end+1..bottom_end-1).each { |y| pad.write(size.x-2, y, '|') }
    pad.write(size.x-2, bottom_end, 'o')
  end

  def render
    super

    last_visible_y = -1
    visible_tweets.each.with_index do |tl, i|
      tl.flag_rerender if @prev_visible_tweets[i] != tl
      tl.render
      last_visible_y = tl.pos.y
    end
    if @prev_last_visible_y > last_visible_y
      rerender_pad(Coord.new(0, last_visible_y+1), Coord.new(size.x-3, @prev_last_visible_y-last_visible_y))
    end

    @prev_visible_tweets = visible_tweets
    @prev_last_visible_y = last_visible_y
  end

  def rerender
    rerender_pad(Coord.new(size.x-3, 0), Coord.new(3, size.y))
  end

  def draw_statusline
    pad.color(1,1,1,1)
    pad.write(0, height-1, @statusline)
    pad.write(width-1, height-1, @header.ljust(1))
  end

  def on_resize(old_size, new_size)
    return if old_size == new_size
    new_pad(new_size)
    flag_redraw
  end

end

class TitlePanel < Thing

  include HasPad
  include PadHelpers

  def initialize(clients)
    super()
    self.size = screen_width, 4
    @clients = clients
  end

  def redraw
    pad.erase

    pad.color(0,1,1,0, :bold, :reverse)
    pad.write(3, 1, ' TIMELINE ')

    user = " CURRENT USER: @#{@clients.user.screen_name} "
    pad.color(0,1,1,0, :bold, :reverse)
    pad.write(size.x - user.length - 3, 1, user)

    pad.color(0,1,1,1, :bold, :reverse)
    pad.write(0, 2, ''.ljust(size.x))
    pad.write(ColumnDefinitions::COLUMNS[:UsernameColumn], 2, 'USER')
    pad.write(ColumnDefinitions::COLUMNS[:TweetColumn], 2, 'TWEET')
  end

  def rerender
    rerender_pad
  end

  def on_resize(old_size, new_size)
    return if old_size == new_size
    new_pad(new_size)
    flag_redraw
  end

end

class DetailPanel < Thing

  include HasPad
  include PadHelpers
  include ProfileImageWatcher

  attr_accessor :tweetline

  def initialize(config, tweetstore)
    super()
    self.size = screen_width, 9
    @config = config
    watch_store(tweetstore)
  end

  def tick(time)
    if @tweetline != @prev_tweetline or any_profile_image_changed?
      @prev_tweetline = @tweetline
      flag_redraw
    end
  end

  def redraw
    pad.erase
    stop_watching_all_profile_images

    # Draw the infobar
    pad.color(0,0,0,1, :bold, :reverse)
    pad.write(0, 0, ''.ljust(size.x))

    unless @tweetline.is_tweet?
      text = ' NO TWEET SELECTED '
      xPos = (size.x - text.size) / 2
      pad.color(0,0,0,1, :reverse)
      pad.write(xPos, 0, text)
      return
    end

    if @tweetline.retweet?
      xPos = ColumnDefinitions::COLUMNS[:UsernameColumn]
      name = "@#{@tweetline.tweet.retweeted_status.user.screen_name}"
      profile_image = get_and_watch_profile_image(@tweetline.tweet.retweeted_status.user)
      UsernameColumn.draw_username(pad, xPos, 0, name, profile_image, :bold)
      pad.color(0)
      pad.write(xPos-1, 0, ' ')
      xPos += name.length

      pad.color(0,5,0, :bold)
      pad.write(xPos, 0, ' << ')
      xPos += 4

      name = "@#{@tweetline.tweet.user.screen_name}"
      profile_image = get_and_watch_profile_image(@tweetline.tweet.user)
      UsernameColumn.draw_username(pad, xPos, 0, name, profile_image, :bold)
      pad.color(0)
      pad.write(xPos+name.length, 0, ' ')
    else
      name = "@#{@tweetline.tweet.user.screen_name}"
      profile_image = get_and_watch_profile_image(@tweetline.tweet.user)
      pad.color(0)
      pad.write(ColumnDefinitions::COLUMNS[:UsernameColumn]-1, 0, ''.ljust(name.length+2))
      UsernameColumn.draw_username(pad, ColumnDefinitions::COLUMNS[:UsernameColumn], 0, name, profile_image, :bold)
    end

    time = @tweetline.tweet.created_at.getlocal.strftime(' %Y-%m-%d %H:%M:%S ')
    pad.color(1,1,1,1)
    pad.write(size.x-time.length-1, 0, time)

    xPos = ColumnDefinitions::COLUMNS[:UsernameColumn]
    yPos = 2
    @tweetline.tweet_pieces.each do |piece|
      color_code = @config.tweet_colors_detail(piece.type)
      case color_code[0]
        when :none
          nil
        when :username
          name = piece.text
          profile_image = get_and_watch_profile_image(piece.entity)
          UsernameColumn.draw_username(pad, xPos, yPos, name, profile_image, *color_code[1..-1])
          xPos += piece.text_width
        when :whitespace
          pad.color(*color_code[1..-1])
          if piece.entity.data == :tab
            xPos += 2
          end
          pad.write(xPos, yPos, piece.text)
          if piece.entity.data == :newline
            xPos = ColumnDefinitions::COLUMNS[:UsernameColumn]
            yPos += 1
          end
        else
          pad.color(*color_code)
          pad.write(xPos, yPos, piece.text)
          xPos += piece.text_width
      end
    end

  end

  def rerender
    rerender_pad
  end

  def on_resize(old_size, new_size)
    return if old_size.x == new_size.x
    new_pad(new_size.x+1, 10)
    flag_redraw
  end

end

class PostPanel < Thing

  include HasPad
  include PadHelpers

  def initialize
    super
    self.size = screen_width, 6
    self.visible = false
    @time = 0
  end

  def set_target(post, reply_to)
    @post = post
    @reply_to = reply_to
  end

  def tick(time)
    flag_redraw if size.y > 0
    @time += time
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
      pad.write((size.x-5)/2, 1, 'v v v')
    end

    pad.color(r,g,b, :bold, :reverse)
    pad.write(ColumnDefinitions::COLUMNS[:UsernameColumn]-1, 3, @reply_to ? ' COMPOSE REPLY ' : ' COMPOSE UPDATE ')

    # Render the post
    pad.color(1,1,1,1)
    pad.write(ColumnDefinitions::COLUMNS[:UsernameColumn], 5, @post)
    pad.bold
    pad.write(ColumnDefinitions::COLUMNS[:SelectionColumn], 5, '  >')
  end

  def rerender
    if @reply_to
      rerender_pad
    else
      rerender_pad(Coord.new(0, 2), Coord.new(size.x, size.y-2))
    end
  end

  def on_resize(old_size, new_size)
    return if old_size == new_size
    new_pad(new_size)
    flag_redraw
  end

end

class ConfirmPanel < Thing

  include HasPad
  include PadHelpers

  def initialize
    super
    self.size = screen_width, 4
    self.visible = false
    @time = 0
  end

  def set_action(action_type, action_text)
    @action_type = action_type
    @action_text = action_text
  end

  def tick(time)
    flag_redraw(size.y > 0)
    @time += time
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
    rerender_pad
  end

  def on_resize(old_size, new_size)
    return if old_size == new_size
    new_pad(new_size)
    flag_redraw
  end

end

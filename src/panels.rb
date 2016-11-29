#!/usr/bin/env ruby

require 'twitter'
require 'twitter-text'
require 'unicode_utils'
require_relative 'tweetline'
require_relative 'tweetstore'
require_relative 'world/world'

require_relative 'panel_set_consume_input'

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
    @header = nil

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
    @notice_panel = NoticePanel.new(@detail_panel)
    @post_panel = PostPanel.new
    @confirm_panel = ConfirmPanel.new
    @events_panel = EventsPanel.new(@clients, @config)

    self << @title_panel
    self << @tweets_panel
    self << @detail_panel
    self << @notice_panel
    self << @post_panel
    self << @confirm_panel
    self << @events_panel
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
      @events_panel.add_incoming_event(event)
      case event
        when Twitter::Tweet
          # TODO: Deal with duplicates
          # TODO: When it's a retweet of your own tweet, carry over fav and rt count from orig tweet
          # TODO: When it's a retweet of your own tweet, increment your tweet's rt count and the rt count of every rt of that tweet.
          # TODO: Link all RTs of a tweet together somehow?
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
      @clients.rest_concurrently(:reply, @post, @reply_to) do |rest, post, reply_to|
        rest.update(post, in_reply_to_status: reply_to)
      end
    else
      @clients.rest_concurrently(:tweet, @post) { |rest, post| rest.update(post) }
    end
  end

  def on_resize(old_size, new_size)
    return if old_size == new_size
    @title_panel.pos = 0,0
    @tweets_panel.pos = 0,4
    @detail_panel.pos = 0, new_size.y-12
    @notice_panel.pos = 0, new_size.y-4
    @post_panel.pos = 0, new_size.y-9
    @confirm_panel.pos = 0, new_size.y-7
    @events_panel.pos = 0, new_size.y-2
    @title_panel.size = new_size.x, @title_panel.size.y
    @tweets_panel.size = new_size.x, new_size.y-17
    @detail_panel.size = new_size.x, @detail_panel.size.y
    @notice_panel.size = new_size.x, @notice_panel.size.y
    @post_panel.size = new_size.x, @post_panel.size.y
    @confirm_panel.size = new_size.x, @confirm_panel.size.y
    @events_panel.size = new_size.x, @events_panel.size.y
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

  def select_tweet(index, rebuild = true, force_scroll = true)
    @selected = [ 0, [ index, @tweetview.size-1 ].min ].max
    if force_scroll
      if @selected < @next_top
        scroll_top(@selected)
      elsif @selected >= @next_top + size.y
        scroll_top(@selected - size.y + 1)
      end
    end
    @tweetstore.rebuild_reply_tree(selected_tweet) if selected_tweet.is_tweet? and rebuild
  end

  def scroll_top(index, force_select_in_visible = false)
    @next_top = [ 0, [ index, @tweetview.size-1 ].min ].max
    if force_select_in_visible
      if @selected >= @next_top + size.y
        select_tweet(@next_top + size.y - 1)
      elsif @selected < @next_top
        select_tweet(@next_top)
      end
    end
  end

  def update_relations
    visible_tweets.each do |tl|
      if tl.is_tweet?
        tl.set_relations

        if selected_tweet.is_tweet?
          # Retweet of tweet
          if tl.retweet? and
              (tl.tweet.retweeted_tweet.id == selected_tweet.tweet.retweeted_tweet.id or
                  tl.tweet.retweeted_tweet.id == selected_tweet.tweet.id)
            tl.set_relations(:retweet_of_tweet)
          end

          # Original of retweet
          if selected_tweet.retweet? and selected_tweet.tweet.retweeted_tweet.id == tl.tweet.id
            tl.set_relations(:original_of_retweet)
          end

          # Tweet by same user
          if tl.tweet.user.id == selected_tweet.tweet.user.id
            tl.set_relations(:same_user)
          end

          # Tweet in replied-to chain
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
  end

  def tick(time)
    # Set selected tweetlines
    if @prev_selected_vl != selected_tweet
      @prev_selected_vl.select(false) if @prev_selected_vl
      selected_tweet.select
    end

    # Tick and position the tweetlines that are visible
    visible_tweets.each.with_index do |tl, i|
      tl.pos.y = i
      tl.size = size.x-3, tl.size.y
      tl.tick_to(@time, time)
    end

    flag_redraw if @prev_top != @next_top
    update_relations if @prev_top != @next_top or @prev_selected_vl != selected_tweet

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

    favs = 5,0,0, @tweetline.root_tweet.favorite_count == 0 ? '' : " ♥ #{@tweetline.root_tweet.favorite_count} "
    rts = 0,5,0, @tweetline.root_tweet.retweet_count == 0 ? '' : " ⟳ #{@tweetline.root_tweet.retweet_count} "
    time = 1,1,1,1, @tweetline.root_tweet.created_at.getlocal.strftime(' %Y-%m-%d %H:%M:%S ')
    source = 1,1,1,1, " #{@tweetline.root_tweet.source.gsub(/<.*?>/, '')} "
    place = 1,1,1,0, @tweetline.root_tweet.place.nil? ? '' : " ⌖ #{@tweetline.tweet.place.name} "
    xPos = size.x
    [ favs, rts, time, source, place ].reverse_each do |text|
      string = text.last
      color = text[0..-2]
      next if string.empty?
      xPos -= UnicodeUtils.display_width(string)+1
      pad.color(*color)
      pad.write(xPos, 0, string)
    end

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

class NoticePanel < Thing

  include HasPad
  include PadHelpers

  FADE_TIME = 60

  def initialize(detail_panel)
    super()
    @detail_panel = detail_panel
    self.size = screen_width, 1

    @text = ''
    @color = [0]
    @start_time = -2*FADE_TIME
    @time = 0
  end

  def set_notice(text, *color)
    @text = text
    @color = color
    @start_time = @time
  end

  def tick(time)
    flag_redraw if @time <= @start_time+FADE_TIME
    @time += time
  end

  def redraw
    pad.erase

    t = (@time - @start_time).to_f / FADE_TIME
    col = @color.map { |c| ((1.0-t)*c).round }
    pos = (size.x-@text.length)/2

    pad.color(*col)
    pad.write(pos-4, 0, "░▒▓ #{''.ljust(@text.length)} ▓▒░")

    pad.color(*col, :bold, :reverse)
    pad.write(pos-1, 0, " #{@text} ")
  end

  def rerender
    return if @time >= @start_time+FADE_TIME
    rerender_pad
  end

  def flag_rerender(rerender = true)
    super
    @detail_panel.flag_rerender(rerender)
  end

  def on_resize(old_size, new_size)
    return if old_size == new_size
    new_pad(new_size)
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

class EventsPanel < Thing

  module Event
    attr_accessor :event, :display, :size, :x, :stopped, :decay
  end

  class OutEvent
    include Event
    def initialize(rest, display)
      @event = rest
      @display = display
      @size = @display[0].length + PADDING
      @x = 0
      @stopped = false
      @decay = 0
    end
  end

  class InEvent
    include Event
    def initialize(event_type, display, right)
      @event = event_type
      @display = display
      @size = @display[0].length + PADDING
      @x = right
      @stopped = false
      @decay = 0
    end
  end

  class FakeEvent
    include Event
    def initialize(x = 0)
      @event = nil
      @display = ['', 0]
      @size = 0
      @x = x
      @stopped = true
      @decay = 0
    end
    def decay=
    end
  end

  include HasPad
  include PadHelpers

  PADDING = 1
  SPEED_FACTOR = 0.1
  SPEED = 1

  def initialize(clients, config)
    super()
    @clients = clients
    @config = config
    @events_out = { rhs: FakeEvent.new }
    @events_in = [ FakeEvent.new(-10) ]
    self.size = screen_width, 2
  end

  def add_incoming_event(streaming_event)
    type =
        case streaming_event
          when Twitter::Tweet
            # TODO: Detect reply
            :tweet
          when Twitter::Streaming::DeletedTweet
            :delete
          when Twitter::Streaming::Event
            streaming_event.name
          else
            :nil
        end
    display = @config.event_in_display(type)
    if display
      @events_in << InEvent.new(type, display, size.x)
      flag_redraw
    end
  end

  def tick(time)
    # Add new outgoing events
    old_size = @events_out.size
    @clients.outgoing_requests.each do |r|
      @events_out[r] = OutEvent.new(r, @config.event_out_display(r.name)) unless @events_out[r]
    end
    flag_redraw if old_size != @events_out.size

    # Move events
    ([:rhs] + @clients.outgoing_requests).each_cons(2) do |rhs, lhs|
      left = @events_out[lhs]
      right = @events_out[rhs]
      if !left.stopped
        x_old = left.x
        # Move the left event right by SPEED_FACTOR of the distance to the right event
        left.x += (SPEED_FACTOR*(right.x-left.size-left.x)).ceil
        # Make sure events don't overlap
        left.x = [ left.x, right.x-left.size ].min
        left.stopped = true if left.x == x_old
      elsif [ :success, :failure ].include?(left.event.status)
        left.decay += 1
      end
    end

    @events_in.each_cons(2) do |left, right|
      # Move right event left by SPEED
      right.x -= SPEED
      # Make sure events don't overlap
      right.x = [ left.x+left.size, right.x ].max
    end

    flag_redraw if @events_out.size > 1 or @events_in.size > 1

    # Delete decayed events
    old_sizes = [ @events_out.size, @events_in.size ]
    @clients.outgoing_requests.delete_if { |r| @events_out[r].decay >= 30 }
    @events_out.delete_if { |_, e| e.decay >= 30 }
    @events_in.delete_if.with_index { |e, i| i > 0 && e.x + e.size < 0 }
    flag_redraw if old_sizes != [ @events_out.size, @events_in.size ]
  end

  def redraw
    pad.erase

    @events_out.each_value do |e|
      if e.event and e.x >= 0
        name = e.display[0]
        color = e.display[1..-1]
        if e.stopped
          if e.event.status == :success and e.decay > 15
            pad.color(0, (5.0*(30-e.decay)/15.0).round, 0)
            gibberish = (1..name.length).map{ (33+rand(15)).chr }.join
            pad.write(e.x, 0, gibberish)
          elsif e.event.status == :failure
            pad.color(4,0,0, :bold)
            pad.write(e.x, 0, name)
          else
            pad.color(*color)
            pad.write(e.x, 0, name)
          end
        else
          pad.color(*color)
          pad.write(e.x, 0, name)
        end
      end
    end

    @events_in.each do |e|
      if e.x >= 0
        name = e.display[0]
        color = e.display[1..-1]
        pad.color(*color)
        pad.write(e.x, 1, name)
      end
    end

    pad.color(0,0,0,1)
    pad.write(0, 0, 'OUT > ')
    pad.write(0, 1, '<<<<< ')
    pad.write(size.x-6, 0, ' >>>>>')
    pad.write(size.x-6, 1, ' < IN ')
  end

  def rerender
    rerender_pad
  end

  def on_resize(old_size, new_size)
    return if old_size == new_size
    @events_out[:rhs].x = new_size.x-5
    new_pad(new_size)
    flag_redraw
  end

end
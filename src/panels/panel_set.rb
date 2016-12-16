require 'clipboard'
require 'launchy'
require 'twitter'
require 'twitter-text'
require 'unicode_utils'
require_relative 'tweets_panel'
require_relative 'detail_panel'
require_relative 'post_panel'
require_relative 'minor_panels'
require_relative '../tweet'
require_relative '../tweetline'
require_relative '../tweetstore'
require_relative '../world/world'

require_relative 'panel_set_consume_input'

class PanelSet < ThingContainer

  include HasWindow
  include PanelSetConsumeInput

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

    @time = 0

    @title_panel = TitlePanel.new(@clients)
    @tweets_panel = TweetsPanel.new(@tweetstore, @title_panel)
    @detail_panel = DetailPanel.new(@config, @tweetstore)
    @notice_panel = NoticePanel.new(@detail_panel)
    @post_panel = PostPanel.new
    @confirm_panel = ConfirmPanel.new
    @events_panel = EventsPanel.new(@clients, @config)

    focus_panel(@tweets_panel)

    self << @title_panel
    self << @tweets_panel
    self << @detail_panel
    self << @notice_panel
    self << @post_panel
    self << @confirm_panel
    self << @events_panel
  end

  def focus_panel(panel)
    if @focused_panel != panel
      @focused_panel.focused = false if @focused_panel
      @focused_panel = panel
      @focused_panel.focused = true
    end
  end

  def post_tweet(post:, reply_to:)
    # The first at-mention in the tweet must match the user being replied to,
    # otherwise don't count it as a reply
    # TODO Make it check the first at-mention, not just any at-mention
    if reply_to and reply_to.user != @clients.user and !post.include?("@#{reply_to.user.screen_name}")
      reply_to = nil
    end

    if reply_to
      @clients.rest_concurrently(:reply, post, reply_to) do |rest, post, reply_to|
        rest.update(post, in_reply_to_status: reply_to)
      end
    else
      @clients.rest_concurrently(:tweet, post) { |rest, post| rest.update(post) }
    end
  end

  def scroll_top(index)
    @tweets_panel.scroll_top(index)
  end

  def select_tweet(index, rebuild = true)
    @tweets_panel.select_tweet(index, rebuild)
  end

  def selected_tweet
    @tweets_panel.selected_tweet
  end

  def selected_index
    @tweets_panel.selected_index
  end

  def set_notice(*args)
    @notice_panel.set_notice(*args)
  end

  def switch_mode(mode)
    return switch_mode(@prev_mode) if @prev_mode and mode == :previous_mode

    @post_panel.visible = false
    @confirm_panel.visible = false

    @prev_mode = @mode
    @mode = mode
    case mode
      when :timeline
        focus_panel(@tweets_panel)
        @detail_panel.flag_rerender
      when :post
        focus_panel(@post_panel)
        @post_panel.visible = true
      when :confirm
        focus_panel(@confirm_panel)
        @confirm_panel.visible = true
      when :detail
        focus_panel(@detail_panel)
    end
  end

  def top
    @tweets_panel.top
  end

  def tweetview
    @tweets_panel.tweetview
  end

  def visible_tweets
    @tweets_panel.visible_tweets
  end

  def tick(time)
    @time += time

    # Consume events from streaming
    until @clients.stream_queue.empty?
      event = @clients.stream_queue.pop
      @events_panel.add_incoming_event(event)
      case event
        when Twitter::Tweet
          # TODO: Seperate adding to store and adding to views; perhaps don't add duplicates to views
          # If we can scroll down one tweet without the selection arrow
          # disappearing, then do so, but only if the view is full
          scroll_top(top+1) if selected_index > top && top + @tweets_panel.size.y == tweetview.size
          @tweetstore << TwepicTweet.new(event.retweeted_tweet, @tweetstore) if event.retweet?
          tweet = TwepicTweet.new(event, @tweetstore)
          @tweetstore << tweet
          @tweetstore << TweetLine.new(@tweets_panel, tweet, @time)
          # If the selection arrow was on the streaming spinner, then follow it
          select_tweet(selected_index+1) if selected_index == tweetview.size-2

        when Twitter::Streaming::DeletedTweet
          @tweetstore.delete_id(event.id)
          # TODO: Instead of shifting everything up, attempt to keep @selected on the same y-position
          # TODO: Decrement retweet count of deleted retweets' root tweets
          select_tweet(selected_index)

        when Twitter::Streaming::Event
          case event.name
            when :access_revoked
              nil
            when :block, :unblock
              nil
            when :favorite, :unfavorite
              tweet = @tweetstore.fetch(event.target_object.id)
              if tweet
                if event.target_object.user.id == @clients.user.id
                  tweet.favorites += 1 if event.name == :favorite
                  tweet.favorites -= 1 if event.name == :unfavorite
                else
                  tweet.favorited = true if event.name == :favorite
                  tweet.favorited = false if event.name == :unfavorite
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
      unless @focused_panel.consume_input(input)
        consume_input(input)
      end
    end

    # Tick panels
    @detail_panel.tweetline = selected_tweet

    self.size = screen_width, screen_height

    super
  end

  def render
    super
    world.rerender
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

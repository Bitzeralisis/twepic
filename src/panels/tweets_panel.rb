require_relative 'panel'
require_relative '../config'
require_relative '../world/window'

class TitlePanel < Panel

  include HasPad
  include PadHelpers

  def initialize(clients)
    super()
    self.size = screen_width, 4
    @clients = clients
  end

  def redraw
    pad.erase

    color1 = @focused ? [ 0,1,1,1, :bold, :reverse ] : [ 0,0,0,1, :bold, :reverse ]
    color2 = @focused ? [ 0,1,1,0, :bold, :reverse ] : [ 0,0,0,1, :bold, :reverse ]

    pad.color(*color2)
    pad.write(3, 1, ' TIMELINE ')

    user = " CURRENT USER: @#{@clients.user.screen_name} "
    pad.color(*color2)
    pad.write(size.x - user.length - 3, 1, user)

    pad.color(*color1)
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

class TweetsPanel < Panel

  include HasPad
  include PadHelpers

  def initialize(tweetstore, title_panel)
    super()
    self.size = screen_width, screen_height-15

    @tweetstore = tweetstore
    @tweetview = @tweetstore.create_view(self)
    @title_panel = title_panel

    @prev_top = -1
    @next_top = 0
    @prev_selected_vl = nil
    @selected = 0
    @prev_visible_tweets = []
    @prev_last_visible_y = -1

    @time = 0
  end

  def focused=(rhs)
    super
    @title_panel.focused=(rhs)
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
          if tl.retweet? and tl.root_tweet.id == selected_tweet.root_tweet.id
            tl.set_relations(:retweet_of_tweet)
          end

          # Original of retweet
          if selected_tweet.retweet? and selected_tweet.root_tweet.id == tl.tweet.id
            tl.set_relations(:original_of_retweet)
          end

          # Tweet by same user
          if tl.tweet.user.id == selected_tweet.tweet.user.id
            tl.set_relations(:same_user)
          end

          # Tweet in replied-to chain
          if @tweetstore.reply_tree.size > 1 and @tweetstore.reply_tree.include?(tl.underlying_tweet)
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

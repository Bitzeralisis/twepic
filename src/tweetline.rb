#!/usr/bin/env ruby

require 'ncursesw'
require 'set'
require 'unicode_utils'
require_relative 'column'
require_relative 'window'

class TweetLine

  include HasPad

  attr_reader :store
  attr_reader :tweet

  attr_reader :selected
  attr_reader :relations
  attr_writer :favorited

  attr_reader :replies_to_this

  def initialize(parent, store, tweet, time)
    new_pad(1, 1)

    @parent = parent
    @store = store
    @tweet = tweet
    @time = time

    @selected = false
    @relations = :none
    @favorited = @tweet.favorited?

    @columns = {}
    ColumnDefinitions::COLUMNS.each_key do |column_type|
      @columns[column_type] = Object::const_get(column_type).new(self)
    end

    @store.check_profile_image(@tweet.user)
    @store.check_profile_image(@tweet.retweeted_tweet.user) if retweet?

    # TODO: Determine if this tweet was replied to by any other tweet in the store
    @replies_to_this = []

    if @tweet.reply?
      replied_to = @store.fetch(@tweet.in_reply_to_status_id)
      replied_to.replies_to_this << self if replied_to
      @store.rebuild_reply_tree if @store.reply_tree.include?(replied_to)
    end
  end

  def tweet=(value)
    @tweet = value
    flag_redraw
  end

  def favorited?
    @favorited
  end

  def mention?
    @_isMention ||= tweet.full_text.downcase.include?("@#{@parent.clients.user.screen_name.downcase}")
  end

  def own_tweet?
    @_isOwnTweet ||= tweet.user.id == @parent.clients.user.id
  end

  def retweet?
    @tweet.retweet?
  end

  def flag_redraw(redraw = true)
    @columns.each_value { |c| c.flag_redraw(redraw) }
  end

  def flag_rerender(rerender = true)
    @rerender = rerender
    @columns.each_value { |c| c.flag_rerender(rerender) }
  end

  def select(selected = true)
    @selected = selected
    flag_rerender
  end

  def set_relations(relation = :none)
    @relations = relation
  end

  def tick_to(time)
    @columns.each_value { |c| c.tick(time-@time) }
    @time = time
  end

  def draw(*options)
    # TODO: Have some way of obliterating the entire line, so if a tweetline replaces something else
    #       there's no random remaining text
    @columns.each_value { |c| @rerender = c.draw || @rerender }
  end

  def render(y)
    return unless @rerender
    (ColumnDefinitions::COLUMNS_BY_X + [[:nil, -3]]).each_cons(2) do |column_def, next_column|
      type = column_def.first
      l = column_def.last
      r = next_column.last
      l += @parent.world.width if l < 0
      r += @parent.world.width if r < 0
      @columns[type].render(l, y, r-l, 1)

      if @selected
        # Draw one space of padding around columns to clear the selection dot there
        # TODO: Don't obliterate text from the previous/next columns with this
        render_range = @columns[type].render_range
        if render_range.size > 0
          lp = l + [ 0, render_range.min ].max
          rp = l + [ render_range.max, r-l-1 ].min
          self.render_pad(0, 0, lp-1, y, lp, y)
          self.render_pad(0, 0, rp+1, y, rp+2, y)
        end
      end
    end
    @rerender = false
  end

end

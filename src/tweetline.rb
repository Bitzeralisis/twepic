#!/usr/bin/env ruby

require 'ncursesw'
require 'set'
require 'unicode_utils'
require_relative 'column'
require_relative 'world/thing'
require_relative 'world/window'

class ViewLine < Thing

  def column_mappings
    {
        SelectionColumn: :SelectionColumn,
        FlagsColumn: :EmptyColumn,
        UsernameColumn: :EmptyColumn,
        RelationsColumn: :EmptyColumn,
        TweetColumn: :EmptyColumn,
        EntitiesColumn: :EmptyColumn,
        TimeColumn: :EmptyColumn,
    }
  end

  include HasPad
  include PadHelpers

  attr_reader :selected

  def initialize(parent)
    super()

    @parent = parent
    @world = @parent.world

    @selected = false
  end

  def is_tweet?
    false
  end

  def select(selected = true)
    if @selected != selected
      @selected = selected
      flag_redraw
    end
  end

  def tick_to(_, time)
    @columns.each_value { |c| c.tick(time) }
  end

  def draw
    super
    @columns.each_value(&:draw)
  end

  def render
    super

    @columns.each_value do |col|
      rendered = col.render
      if @selected and rendered
        # Draw one space of padding around columns to clear the selection dot there
        if col.size.x > 0
          gpos = global_pos
          lp = gpos.x + col.pos.x + [ 0, col.clip.x ].max
          rp = gpos.x + col.pos.x + [ col.clip.x+col.size.x-1, col.max_size.x-1 ].min
          pad.render_pad(size.x, 0, lp-1, gpos.y, lp-1, gpos.y)
          pad.render_pad(size.x, 0, rp+1, gpos.y, rp+1, gpos.y)
        end
      end
    end
  end

  def flag_rerender(rerender = true)
    super(rerender)
    @columns.each_value { |c| c.flag_rerender(rerender) }
  end

  def on_resize(old_size, new_size)
    return if new_size == old_size
    resize_columns
    flag_rerender
  end

  private

  def create_columns
    @columns = {}
    ColumnDefinitions::COLUMNS.each_key do |column_type|
      @columns[column_type] = Object::const_get(column_mappings[column_type]).new(self)
      @columns[column_type].parent = self
    end
    resize_columns
  end

  def resize_columns
    (ColumnDefinitions::COLUMNS_BY_X + [[:nil, size.x]]).each_cons(2) do |column_def, next_column|
      type = column_def.first
      l = column_def.last
      r = next_column.last
      l += size.x if l < 0
      r += size.x if r < 0
      @columns[type].pos.x = l
      @columns[type].max_size.x = r-l-1
    end
  end

end

class TweetLine < ViewLine

  attr_reader :relations

  def column_mappings
    super.merge({
        FlagsColumn: :FlagsColumn,
        UsernameColumn: :UsernameColumn,
        RelationsColumn: :RelationsColumn,
        TweetColumn: :TweetColumn,
        EntitiesColumn: :EntitiesColumn,
        TimeColumn: :TimeColumn,
    })
  end

  def initialize(parent, tweet, time)
    super(parent)
    @size = Coord.new(parent.size.x-3, 1)
    new_pad(size.x+1, 1)

    @tweet_id = tweet.tweet.id
    @store = tweet.store
    @time = time
    @relations = :none

    create_columns
  end

  def method_missing(m, *args, &block)
    # TODO: Maybe we don't want to do this and just write functions to read everything that's needed
    underlying_tweet.send(m, *args, &block)
  end

  def is_tweet?
    true
  end

  def set_relations(relation = :none)
    @relations = relation
  end

  def underlying_tweet
    @_underlying_tweet ||= @store.fetch(@tweet_id)
  end

  def underlying_tweet_changed
    @_underlying_tweet = nil
  end

  def tick_to(time, _)
    @columns.each_value { |c| c.tick(time-@time) }
    @time = time
  end

  def redraw
    pad.erase

    # Clear/draw selection dots
    if @selected
      if has_wide_characters?
        # Avoid rendering dots where the tweet would appear to prevent it from fucking up
        left = @columns[:TweetColumn].pos.x
        right = left + underlying_tweet.text_width
        pad.color(0,0,0,1, :dim)
        pad.write(0, 0, ''.ljust(left, '·'))
        pad.write(right, 0, ''.ljust(size.x-right, '·'))
      else
        pad.color(0,0,0,1, :dim)
        pad.write(0, 0, ''.ljust(size.x, '·'))
      end
    end

    if false
      # Debug stuff: prints a bold `#` instead of ` ` for padding around columns
      pad.color(1,1,1,1, :bold)
      pad.write(size.x, 0, '#')
    end
  end

  def rerender
    rerender_pad
  end

  def on_resize(old_size, new_size)
    super
    return if new_size == old_size
    new_pad(new_size)
    flag_redraw
  end

end

class StreamLine < ViewLine

  def column_mappings
    super.merge({
        TweetColumn: :StreamingColumn,
    })
  end

  def initialize(parent)
    super
    @size = Coord.new(parent.size.x-3, 1)
    new_pad(size.x, size.y)
    create_columns
  end

  def is_tweet?
    false
  end

  def redraw
    pad.erase
  end

  def rerender
    rerender_pad
  end

  def on_resize(old_size, new_size)
    super
    return if new_size == old_size
    new_pad(new_size)
    flag_redraw
  end

end

class FoldLine < ViewLine

  def initialize(parent)
    super
    @folded_lines = []
    @size = Coord.new(parent.size.x-3, 1)
    create_columns
    new_pad(size.x, size.y)
  end

  def is_tweet?
    false
  end

  def <<(rhs)
    @folded_lines << rhs
    flag_redraw
  end

  def redraw
    pad.erase

    num_rts = @folded_lines.size
    num_rters = @folded_lines.uniq { |tl| tl.tweet.user.id }.size
    num_rtds = @folded_lines.uniq { |tl| tl.retweeted_tweet.user.id }.size

    pad.color(0,0,0,1)
    pad.write(0, 0, " #{num_rts} FOLDED RETWEETS by #{num_rters} USER(S) of #{num_rtds} USER(S) ".center(size.x, '-'))
  end

  def rerender
    rerender_pad
  end

  def on_resize(old_size, new_size)
    super
    return if new_size == old_size
    new_pad(new_size)
    flag_redraw
  end

end

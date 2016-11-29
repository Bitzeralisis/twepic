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

  attr_reader :store
  attr_reader :tweet
  attr_reader :tweet_pieces

  attr_reader :relations
  attr_writer :favorited
  attr_accessor :favorites

  attr_reader :replies_to_this

  def initialize(parent, store, tweet, time)
    super(parent)
    @size = Coord.new(parent.size.x-3, 1)
    new_pad(size.x+1, 1)

    @store = store
    @tweet = tweet
    @time = time

    @relations = :none
    @favorited = @tweet.favorited?
    @favorites = @tweet.favorite_count

    build_tweet_pieces
    create_columns

    @store.check_profile_image(@tweet.user)
    @store.check_profile_image(@tweet.retweeted_tweet.user) if retweet?
    @tweet.user_mentions.each do |mention|
      if @store.get_profile_image(mention).nil?
        user = @store.clients.rest_api.user(mention.id)
        @store.check_profile_image(user)
      end
    end

    # TODO: Determine if this tweet was replied to by any other tweet in the store
    @replies_to_this = []

    if @tweet.reply?
      replied_to = @store.fetch(@tweet.in_reply_to_status_id)
      replied_to.replies_to_this << self if replied_to
      @store.rebuild_reply_tree if @store.reply_tree.include?(replied_to)
    end
  end

  def is_tweet?
    true
  end

  def tweet=(value)
    @tweet = value
    # TODO: Probably want to do all the other stuff like building reply tree or something
    flag_redraw
  end

  def extended_text
    retweet? ? "RT @#{@tweet.retweeted_tweet.user.screen_name}: #{root_extended_text}" : root_extended_text
  end

  def favorited?
    @favorited
  end

  def has_wide_characters?
    @text_width != @text_length
  end

  def mention?
    @_isMention ||= extended_text.downcase.include?("@#{@store.clients.user.screen_name.downcase}")
  end

  def own_tweet?
    @_isOwnTweet ||= tweet.user.id == @store.clients.user.id
  end

  def root_extended_entities
    h = root_tweet.to_h

    original_entities = h[:entities]
    h[:entities] = h[:extended_tweet][:entities] if h[:extended_tweet]
    entities = root_tweet.user_mentions + root_tweet.urls + root_tweet.media + root_tweet.hashtags
    h[:entities] = original_entities

    entities
  end

  def root_extended_text
    h = root_tweet.to_h
    retval ||= h[:full_text] # Long tweets from REST with `tweet_mode: extended`
    retval ||= h[:extended_tweet][:full_text] if h[:extended_tweet] # Long tweets from streaming
    retval ||  h[:text] # Classic tweets from REST without special options
  end

  def root_tweet
    retweet? ? tweet.retweeted_tweet : tweet
  end

  def retweet?
    @tweet.retweet?
  end

  def set_relations(relation = :none)
    @relations = relation
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
        right = left + @text_width
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

  private

  def build_tweet_pieces
    # Transform entities. We do this by making a sorted list of entities we care about, splitting
    # the tweet based on their indices, transforming the pieces that correspond to entities, and
    # rejoining all the pieces
    full_text = root_extended_text
    text_type =
      if retweet?
        :text_retweet
      elsif mention?
        :text_mention
      elsif own_tweet?
        :text_own_tweet
      else
        :text_normal
      end

    entities = root_extended_entities
    entities.sort! { |lhs, rhs| lhs.indices.first <=> rhs.indices.first }
    entities.uniq! { |e| e.indices.first }
    entities = [ FakeEntity.new([0]) ] + entities + [ FakeEntity.new([full_text.length]) ]

    tweet_pieces = []
    entities.each_cons(2) do |entity, next_entity|
      case entity
        when Twitter::Entity::UserMention
          tweet_pieces << TweetPiece.new(entity, :mention_username, full_text[entity.indices.first...entity.indices.last])
        when Twitter::Entity::Hashtag
          tweet_pieces << TweetPiece.new(entity, :hashtag, full_text[entity.indices.first...entity.indices.last])
        when Twitter::Media::AnimatedGif, Twitter::Media::Photo, Twitter::Media::Video, Twitter::Entity::URL
          slash_index = entity.display_url.index('/')
          if slash_index.nil?
            tweet_pieces << TweetPiece.new(entity, :link_domain, entity.display_url)
          else
            tweet_pieces << TweetPiece.new(entity, :link_domain, entity.display_url[0...slash_index])
            tweet_pieces << TweetPiece.new(entity, :link_route, entity.display_url[slash_index..-1])
          end
        else
          nil # Do nothing - the entity is discarded
      end
      tweet_pieces << TweetPiece.new(nil, text_type, full_text[entity.indices.last...next_entity.indices.first])
    end

    if retweet?
      # Put `RT @retweeted_username ` in front of retweets
      retweeted_user_entity = @tweet.user_mentions.first
      tweet_pieces.unshift(
          TweetPiece.new(nil, :retweet_marker, 'RT '),
          TweetPiece.new(retweeted_user_entity, :retweet_username, "@#{retweeted_user_entity.screen_name} ")
      )
    end

    tweet_pieces.each { |piece| piece.text = $htmlentities.decode(piece.text) }
    tweet_pieces = tweet_pieces.flat_map do |piece|
      # TODO: Combine consecutive newlines and tabs, filter out empty strings
      piece.text.split(/(\r\n|\r|\n|\t)/).map do |string|
        case string
          when "\r\n", "\r", "\n"
            TweetPiece.new(FakeEntity.new(:newline), :whitespace, '↵ ')
          when "\t"
            TweetPiece.new(FakeEntity.new(:tab), :whitespace, '⇥ ')
          else
            TweetPiece.new(piece.entity, piece.type, string)
        end
      end
    end

    @tweet_pieces = tweet_pieces
    @text_width = @tweet_pieces.map { |piece| piece.text_width }.reduce(0, :+)
    @text_length = @tweet_pieces.map { |piece| piece.text.length }.reduce(0, :+)
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

class FakeEntity
  attr_reader :data
  def initialize(data)
    @data = data
  end
  def indices
    data
  end
end

class TweetPiece
  attr_accessor :entity, :type
  attr_reader :text
  def initialize(entity, type, text)
    @entity = entity
    @type = type
    @text = text
  end
  def text=(val)
    @text = val
    @_text_width = nil
  end
  def text_width
    @_text_width ||= UnicodeUtils.display_width(@text)
  end
end


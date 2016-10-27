#!/usr/bin/env ruby

require 'ncursesw'
require 'set'
require 'unicode_utils'
require_relative 'column'
require_relative 'world/window'

class TweetLine

  include HasPad

  attr_reader :store
  attr_reader :tweet
  attr_reader :tweet_pieces

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

    build_tweet_pieces

    @selected = false
    @relations = :none
    @favorited = @tweet.favorited?

    @columns = {}
    ColumnDefinitions::COLUMNS.each_key do |column_type|
      @columns[column_type] = Object::const_get(column_type).new(self)
    end

    @store.check_profile_image(@tweet.user)
    @store.check_profile_image(@tweet.retweeted_tweet.user) if retweet?
    @tweet.user_mentions.each do |mention|
      if @store.get_profile_image(mention).nil?
        user = @parent.clients.rest_api.user(mention.id)
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

  def tweet=(value)
    @tweet = value
    # TODO: Probably want to do all the other stuff like building reply tree or something
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

  private

  def build_tweet_pieces
    # Transform entities. We do this by making a sorted list of entities we care about, splitting
    # the tweet based on their indices, transforming the pieces that correspond to entities, and
    # rejoining all the pieces
    full_text = @tweet.full_text
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

    entities = @tweet.user_mentions + @tweet.urls + @tweet.media + @tweet.hashtags
    entities.sort! { |lhs, rhs| lhs.indices.first <=> rhs.indices.first }
    entities.uniq! { |e| e.indices.first }
    entities = [ FakeEntity.new([0]) ] + entities + [ FakeEntity.new([full_text.length]) ]
    if retweet?
      # Where [] denotes an entity, the tweet starts like '[]RT [@username]: text...'
      # Put in the new FakeEntity {} to get rid of the colon '[]RT [@username]{:} text...'
      colon_index = full_text.index(':')
      entities.insert(2, FakeEntity.new([colon_index, colon_index+1]))
    end

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
      # See above; piece 0 is 'RT', piece 1 is "@#{username}", 2 is '', 3 is the text
      tweet_pieces[0].type = :retweet_marker
      tweet_pieces[1].type = :retweet_username
      # These next two lines move the space between the rt'd user's username and the beginning of
      # the text from being at the beginning of the text to after the username. This way, if :none
      # is used to render the username, it will also get rid of the space after it
      tweet_pieces[1].text << ' '
      tweet_pieces[3].text[0] = ''
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


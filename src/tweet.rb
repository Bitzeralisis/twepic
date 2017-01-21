class TwepicTweet

  attr_reader :tweet
  attr_reader :tweet_pieces
  attr_reader :text_length
  attr_reader :text_width
  attr_reader :store

  attr_writer :favorited
  attr_accessor :favorites
  attr_reader :replies_to_this

  def initialize(tweet, store)
    @tweet = tweet
    @store = store
    @retweet_id = tweet.retweeted_tweet.id if tweet.retweet?

    @favorited = @tweet.favorited?
    @favorites = @tweet.favorite_count

    build_tweet_pieces

    @store.check_profile_image(@tweet.user)
    #@store.check_profile_image(@tweet.retweeted_tweet.user) if @tweet.retweet?
    @tweet.user_mentions.each do |mention|
      @store.clients.rest_concurrently(:nil, mention.id, store) do |rest, id, store|
        if store.get_profile_image(mention).nil?
          user = rest.user(id)
          store.check_profile_image(user)
        end
      end
    end

    # TODO: Determine if this tweet was replied to by any other tweet in the store
    # Only going to be a problem once we start fetching tweets from the past
    @replies_to_this = []

    if @tweet.reply?
      replied_to = @store.fetch(@tweet.in_reply_to_status_id)
      replied_to.replies_to_this << self if replied_to
      @store.rebuild_reply_tree if @store.reply_tree.include?(replied_to)
    end
  end

  def extended_text
    retweet? ? "RT @#{retweeted_tweet.user.screen_name}: #{root_extended_text}" : root_extended_text
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

  def retweeted_tweet
    retweeted_twepic_tweet.tweet
  end

  def retweeted_twepic_tweet
    @_retweeted_twepic_tweet ||= @store.fetch(@retweet_id)
  end

  def retweeted_tweet_changed
    @_retweeted_twepic_tweet = nil
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
    retweet? ? retweeted_tweet : tweet
  end

  def root_twepic_tweet
    retweet? ? retweeted_twepic_tweet : self
  end

  def retweet?
    @tweet.retweet?
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
            domain = TweetPiece.new(entity, :link_domain, entity.display_url[0...slash_index])
            route  = TweetPiece.new(entity, :link_route, entity.display_url[slash_index..-1])
            domain.grouped_with += [ route ]
            route.grouped_with += [ domain ]
            tweet_pieces << domain
            tweet_pieces << route
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
      # TODO: Filter out empty strings
      split = piece.text.split(/(\r\n|\r|\n|\t)/)
      if split.size == 1
        # Don't make new pieces for non-split pieces so groupings are preserved
        piece
      else
        split.map do |string|
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
    end

    @tweet_pieces = tweet_pieces
    @text_width = @tweet_pieces.map { |piece| piece.text_width }.reduce(0, :+)
    @text_length = @tweet_pieces.map { |piece| piece.text.length }.reduce(0, :+)
  end

end

class TweetPiece
  attr_accessor :entity, :type
  attr_reader :text
  attr_accessor :grouped_with
  def initialize(entity, type, text, grouped_with: [])
    @entity = entity
    @type = type
    @text = text
    @grouped_with = [ self ] + grouped_with
  end
  def text=(val)
    @text = val
    @_text_width = nil
  end
  def text_width
    @_text_width ||= UnicodeUtils.display_width(@text)
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

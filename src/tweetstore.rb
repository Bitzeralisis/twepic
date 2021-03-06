#!/usr/bin/env ruby

require 'open-uri'
require 'rmagick'
require 'twitter'

class TweetStore

  attr_reader :clients
  attr_reader :config
  attr_reader :reply_tree

  def initialize(config, clients)
    @config = config
    @clients = clients

    @tweets_index = {}
    @retweets_index = {}
    @reply_tree_node = nil
    @reply_tree = []

    @views = []

    @profile_urls = {}
    @profile_images = {}
    @profile_image_requests = Queue.new
    @profile_image_worker = Thread.new { profile_image_worker(@profile_image_requests) }
  end

  def <<(tweet)
    case tweet
      when TwepicTweet
        id = tweet.tweet.id
        if @tweets_index[id]
          @views.each { |v| v.each { |tl| tl.underlying_tweet_changed if tl.is_tweet? && tl.tweet.id == id } }
          (@retweets_index[id] || []).each { |t| t.retweeted_tweet_changed }
        end
        @tweets_index[id] = tweet

        if tweet.retweet?
          rt_id = tweet.tweet.retweeted_tweet.id
          @retweets_index[rt_id] ||= []
          @retweets_index[rt_id] << tweet
        end

      when TweetLine
        @views.each { |v| v.stream(tweet) }
    end
  end

  def delete_id(id)
    @views.each { |v| v.delete_if { |tl| tl.is_tweet? && tl.tweet.id == id } }
    @tweets_index.delete(id)
  end

  def each
    @tweets_index.each_value { |t| yield(t) }
  end

  def fetch(id)
    @tweets_index[id]
  end

  def size
    @tweets_index.size
  end

  # Actual methods that do stuff

  def attach_view(view)
    @views << view
  end

  def check_profile_image(user)
    @profile_image_requests << user
  end

  def get_profile_image(user)
    @profile_images[user.id]
  end

  def rebuild_reply_tree(*args)
    # Use the passed TL as the node to build the reply tree on
    # If not passed anything, use the previously used TL
    tweet = @reply_tree_node if args.size == 0
    tweet ||= args[0]
    tweet = tweet.underlying_tweet if tweet.instance_of? TweetLine
    @reply_tree_node = tweet

    # Put entire child tree in
    @reply_tree = [tweet]
    @reply_tree.each do |r|
      r.replies_to_this.each do |t|
        @reply_tree << t unless @reply_tree.include?(t)
      end
    end

    # Add only path to root node of tree
    current_tweet = tweet
    while current_tweet.tweet.reply?
      t = fetch(current_tweet.tweet.in_reply_to_status_id)
      break unless t
      @reply_tree << t
      current_tweet = t
    end

    @reply_tree.sort! { |l, r| l.tweet.id - r.tweet.id }
  end

  private

  def profile_image_worker(queue)
    while true
      user = queue.pop

      id = user.id
      # TODO: get the 24x24 version of the profile image instead
      url = user.profile_image_url
      if @profile_urls[id] != url
        @profile_urls.delete(id)
        @profile_images.delete(id)
        begin
          open(url, 'rb') do |f|
            image = Magick::Image::from_blob(f.read)[0]
            # Normal brightness, saturation x 10
            image = image.modulate(1.0, 10.0)
            # Hack to get two most prominent colors (see Wikipedia page for quantize)
            # color_histogram returns a hash of pixels to counts
            hist = image.quantize(2).color_histogram
            col2,col1 = hist.keys.sort { |lhs, rhs| hist[lhs] <=> hist[rhs] }
            col1 ||= col2 # In case of solid-color profile image...
            image = Magick::Image::constitute(2, 1, 'RGB',
                                              [ col1.red, col1.green, col1.blue,
                                                col2.red, col2.green, col2.blue ])
            image = image.resize(user.screen_name.length+1, 1)
            @profile_urls[id] = url
            @profile_images[id] = image
          end
        rescue => e
          # Something went wrong, probably failed to get an image or something
          # TODO: Requeue with limited retries
          $logger.error(e)
          @profile_urls.delete(id)
          @profile_images.delete(id)
        end
      end
    end
  end

end

class TweetView

  attr_accessor :height
  attr_reader :name
  attr_reader :selected
  attr_reader :top

  def initialize(parent, name, &block)
    @parent = parent
    @name = name
    @tweets = []
    @stream_filter = block || lambda { |_| false }

    @selected = 0
    @top = 0
  end

  def <<(tweetline)
    @tweets << tweetline
  end

  def [](*args)
    @tweets[*args]
  end

  def delete_if
    @tweets.delete_if { |t| yield(t) }
    select_tweet(@selected, nil, false)
    scroll_top(@top, nil, false)
  end

  def each
    @tweets.each { |t| yield(t) }
  end

  def find_index
    @tweets.find_index { |t| yield(t) }
  end

  def scroll_top(index, force_select_in_visible = false, height = 0)
    @top = [ 0, [ index, size-1 ].min ].max
    if force_select_in_visible
      if @selected >= @top + height
        select_tweet(@top + height - 1, true, height)
      elsif @selected < @top
        select_tweet(@top, true, height)
      end
    end
  end

  def select_tweet(index, force_scroll = true, height = 0)
    @selected = [ 0, [ index, size-1 ].min ].max
    if force_scroll
      if @selected < @top
        scroll_top(@selected)
      elsif @selected >= @top + height
        scroll_top(@selected - height + 1)
      end
    end
  end

  def size
    @tweets.size
  end

  def stream(tl)
    self << tl if @stream_filter.(tl)
  end

end

class StreamingTweetView < TweetView

  def initialize(parent, name, &block)
    super
    @tweets << StreamLine.new(parent)
  end

  def <<(tweetline)
    if true
      # If we can scroll down one tweet without the selection arrow
      # disappearing, then do so, but only if the view is full
      scroll_top(@top+1) if @selected > @top && @top + @parent.size.y == size
      @tweets.insert(-2, tweetline)
      # If the selection arrow was on the streaming spinner, then follow it
      select_tweet(@selected+1, true, @parent.size.y) if @selected == size-2
    else
      # Code that automatically puts consequtive RTs into a fold. Currently not in use
      last = @tweets[-2] # Ignore the streaming spinner
      if (tweetline.is_tweet? and tweetline.retweet?) and
         ((last and last.is_tweet? and last.retweet?) or
           last.instance_of? FoldLine)
        if last.instance_of? FoldLine
          last << tweetline
        else
          fold = FoldLine.new(@parent)
          fold << last
          fold << tweetline
          @tweets[-2] = fold
        end
      else
        @tweets.insert(-2, tweetline)
      end
    end
  end

end

module ProfileImageWatcher

  def watch_store(tweetstore)
    @piw_tweetstore = tweetstore
    @piw_watches = {}
  end

  def any_profile_image_changed?
    @piw_watches.any? do |user, image|
      image != @piw_tweetstore.get_profile_image(user)
    end
  end

  def get_and_watch_profile_image(user)
    image = @piw_tweetstore.get_profile_image(user)
    @piw_watches[user] = image
    image
  end

  def stop_watching_profile_image(user)
    @piw_watches.delete(user)
  end

  def stop_watching_all_profile_images
    @piw_watches = {}
  end

end


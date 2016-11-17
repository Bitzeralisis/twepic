#!/usr/bin/env ruby

require 'open-uri'
require 'rmagick'

class TweetStore

  attr_reader :clients
  attr_reader :config
  attr_reader :reply_tree

  def initialize(config, clients)
    @config = config
    @clients = clients

    @tweets = []
    @tweets_index = {}
    @reply_tree_node = nil
    @reply_tree = []

    @views = []

    @profile_urls = {}
    @profile_images = {}
    @profile_image_requests = Queue.new
    @profile_image_worker = Thread.new { profile_image_worker(@profile_image_requests) }
  end

  # "Overrides" for Array and Hash methods so TweetStore can be treated like one

  def <<(tweetline)
    @tweets << tweetline
    @tweets_index[tweetline.tweet.id] = tweetline
    @views.each { |v| v << tweetline }
  end

  def [](*args)
    @tweets[*args]
  end

  def delete_id(id)
    @tweets.delete_if { |tl| tl.tweet.id == id }
    @tweets_index.delete(id)
    @views.each { |v| v.delete_if { |tl| tl.is_tweet? && tl.tweet.id == id } }
  end

  def each
    @tweets.each { |t| yield(t) }
  end

  def fetch(id)
    @tweets_index[id]
  end

  def find_index
    @tweets.find_index { |t| yield(t) }
  end

  def size
    @tweets.size
  end

  # Actual methods that do stuff

  def create_view(parent)
    view = TweetView.new(parent)
    @views << view
    view
  end

  def check_profile_image(user)
    @profile_image_requests << user
  end

  def get_profile_image(user)
    @profile_images[user.id]
  end

  def rebuild_reply_tree(*args)
    # Use the passed TL as the node to build the reply tree one
    # If not passed anything, use the previously used TL
    tl = @reply_tree_node if args.size == 0
    tl ||= args[0]
    @reply_tree_node = tl

    # Put entire child tree in
    @reply_tree = [tl]
    @reply_tree.each do |r|
      r.replies_to_this.each do |t|
        @reply_tree << t unless @reply_tree.include?(t)
      end
    end

    # Add only path to root node of tree
    current_tweet = tl
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
        rescue
          # Something went wrong, probably failed to get an image or something
          # TODO: Requeue with limited retries
          @profile_urls.delete(id)
          @profile_images.delete(id)
        end
      end
    end
  end

end

class TweetView

  def initialize(parent)
    streaming = StreamLine.new(parent)
    @tweets = [streaming]
  end

  def <<(tweetline)
    @tweets.insert(-2, tweetline)
  end

  def [](*args)
    @tweets[*args]
  end

  def delete_if
    @tweets.delete_if { |t| yield(t) }
  end

  def each
    @tweets.each { |t| yield(t) }
  end

  def size
    @tweets.size
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
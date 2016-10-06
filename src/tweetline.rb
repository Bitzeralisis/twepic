require 'ncursesw'
require 'open-uri'
require 'rmagick'
require 'unicode_utils'
require_relative 'panels'
require_relative 'window'

class TweetStore

  attr_reader :reply_tree

  def initialize
    @tweets = []
    @tweets_index = {}
    @reply_tree_node = nil
    @reply_tree = []
    @profile_urls = {}
    @profile_images = {}
  end

  # "Overrides" for Array and Hash methods so TweetStore can be treated like one

  def <<(tweetline)
    @tweets << tweetline
    @tweets_index[tweetline.tweet.id] = tweetline
  end

  def [](*args)
    return @tweets[*args]
  end

  def delete_id(id)
    @tweets.delete_if { |tl| tl.tweet.id == id }
    @tweets_index.delete(id)
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
    return @tweets.size
  end

  # Actual methods that do stuff

  def check_profile_image(tl)
    id = tl.tweet.user.id
    # TODO: get the 24x24 version of the profile image instead
    url = tl.tweet.user.profile_image_url
    if @profile_urls[id] != url
      @profile_urls.delete(id)
      @profile_images.delete(id)
      open(url, 'rb') do |f|
        image = Magick::Image::from_blob(f.read)[0]
        # Normal brightness, saturation x 10
        image = image.modulate(1.0, 10.0)
        # Hack to get two most prominent colors (see Wikipedia page for quantize)
        # color_histogram returns a hash of pixels to counts
        hist = image.quantize(2).color_histogram
        col2,col1 = hist.keys.sort { |lhs, rhs| hist[lhs] <=> hist[rhs] }
        col1 ||= col2 # In case of solid-color profile image...
        image = Magick::Image::constitute(2, 1, "RGB",
            [ col1.red, col1.green, col1.blue,
              col2.red, col2.green, col2.blue ])
        image = image.resize(tl.tweet.user.screen_name.length+1, 1)
        @profile_images[id] = image
        @profile_urls[id] = url
      end
    end
  end

  def get_profile_image(user)
    return @profile_images[user.id]
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

end

class TweetLine

  include HasWindow

  PAD_WIDTH = 300

  SELECTION_X = 2
  FLAGS_X = 4
  USERNAME_X = 7
  RELATIONS_X = 26
  TWEET_X = 28
  TWEET_X_END = -8
  ENTITIES_X = -6

  attr_reader :tweet

  attr_reader :replies_to_this

  def initialize(parent, store, tweet, time)
    @window = Ncurses.newpad(1, PAD_WIDTH);

    @parent = parent
    @store = store
    @tweet = tweet
    @time = time

    if RT_UNC
      tweet_body = (retweet? ? @tweet.retweeted_status.text : @tweet.text)
    else
      tweet_body = @tweet.full_text
    end
    tweet_body = $htmlentities.decode(tweet_body)
    tweet_body = tweet_body.gsub(/\r\n/, '↵')
                           .gsub(/[\r\n]/, '↵')
                           .gsub(/\t/, '⇥')
    @text = tweet_body
    @text_width = UnicodeUtils.display_width(@text)
    @appear = 0 # Relative x-position of the head of the trailer
    @appear_chars = 0 # Index into @text which is being rendered
    @prev_selected = false
    @redraw = true

    @store.check_profile_image(self)

    # TODO: Determine if this tweet was replied to by any other tweet in the store
    @replies_to_this = []

    if @tweet.reply?
      replied_to = @store.fetch(@tweet.in_reply_to_status_id)
      replied_to.replies_to_this << self if replied_to
      @store.rebuild_reply_tree if @store.reply_tree.include?(replied_to)
    end
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

  def tick_to(time)
    until @time == time
      @time += 1
      if @appear <= @text_width + TRAILER_WIDTH
        @appear += 1
        if UnicodeUtils.display_width(@text[0, @appear_chars]) < @appear-TRAILER_WIDTH
          @appear_chars += 1
        end
      end
    end
  end

  def do_noutrefresh(i)
    @window.pnoutrefresh(0, FLAGS_X, i, FLAGS_X, i+1, self.width-4)
  end

  def render(*options)
    options = options[0] || {}

    @redraw = (@appear <= @text_width + TRAILER_WIDTH) || (@prev_selected != !!options[:selected])

    if options.delete(:redraw) or @redraw
      render_redraw(options)
    else
      if retweet? and @parent.time%RETWEET_USERNAME_CHANGE_INTERVAL == 0
        render_username if RT_UNC
        # render_flags if own_tweet?
      end
    end
  end

  private

  TRAILER_WIDTH = 20 # Total width of the trailer
  RT_UNC = false # ReTweet UserName Change: When on, username of RTs flash between RT'd and RT-er. When off, username shows RT-er, and tweet text shows "RT @#{RTd}: #{tweet}"
  RETWEET_USERNAME_CHANGE_INTERVAL = 60 # Time RT'd / RT-er's usename displays for before switching

  def render_redraw(options)
    window = self

    window.erase

    if @prev_selected = !!options.delete(:selected)
      window.color(0,0,0,1, :dim)
      window.write(0, 0, ''.ljust(PAD_WIDTH, '·'))
    end

    render_text
    render_username
    # render_flags
    render_entities

    @redraw = false
  end

  def render_text
    window = self

    # Draw the trailer
    right = [ 0, @appear-1 ].max
    left = [ 0, @appear-TRAILER_WIDTH ].max
    if right < @text_width
      # Draw the head of the trailer
      window.color(0,1,0,1, :reverse)
      window.write(TWEET_X+right, 0, ' ')
    end
    if left < @text_width
      # Draw the gibberish text
      gibberish_begin = left
      gibberish_end = [ right, @text_width ].min
      gibberish_len = gibberish_end - gibberish_begin
      gibberish = (1...TRAILER_WIDTH).map{ (33+rand(94)).chr }.join
      gibberish[-4, 4] = '▒▒▒▓'
      gibberish = gibberish[0, gibberish_len] || ''
      window.color(0,1,0,1)
      window.write(TWEET_X+gibberish_begin, 0, gibberish)
    end

    # Draw the tweet itself
    if retweet?
      window.color(4,5,4)
    elsif mention?
      window.color(5,4,3)
    elsif own_tweet?
      window.color(4,5,5)
    else
      window.color(1,1,1,1)
    end
    window.write(TWEET_X, 0, "#{@text[0, @appear_chars]} ")
  end

  def render_username
    window = self

    if RT_UNC and retweet? and (@parent.time/RETWEET_USERNAME_CHANGE_INTERVAL)%2.0 < 1.0
      window.color(4,5,4)
      window.write(USERNAME_X, 0, "@#{@tweet.retweeted_status.user.screen_name} ")
    else
      name = "@#{@tweet.user.screen_name}"
      window.write(USERNAME_X-1, 0, ''.ljust(name.length+2))
      (0...name.length).each do |i|
        profile_image = @store.get_profile_image(tweet.user)
        color = profile_image.pixel_color(i,0)
        r,g,b = [ color.red, color.green, color.blue ]
        r,g,b = [r,g,b].map { |f| (((f/256.0/256.0)*0.89+0.11)*5).round }
        window.color(r,g,b)
        window.write(USERNAME_X+i, 0, name[i])
      end
    end
  end

  def render_flags
    window = self

    if own_tweet? and (not retweet? or (@parent.time/RETWEET_USERNAME_CHANGE_INTERVAL)%2.0 >= 1.0)
      window.color(4,5,5)
      window.write(FLAGS_X, 0, "S")
    elsif retweet?
      window.color(0,5,0)
      window.write(FLAGS_X, 0, "R")
    elsif mention?
      window.color(5,3,1, :bold)
      window.write(FLAGS_X, 0, "M")
    end
  end

  def render_entities
    window = self

    if @tweet.media?
      window.color(1,1,1,0, :bold)
      case @tweet.media[0]
      when Twitter::Media::Photo
        if @tweet.media.size == 1
          window.write(window.width+ENTITIES_X-1, 0, ' img') 
        else
          window.write(window.width+ENTITIES_X-1, 0, " i:#{@tweet.media.size.to_s}") 
        end
      when Twitter::Media::Video
        window.write(window.width+ENTITIES_X-1, 0, ' vid');
      when Twitter::Media::AnimatedGif
        window.write(window.width+ENTITIES_X-1, 0, ' gif');
      end
    end
  end

end

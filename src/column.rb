#!/usr/bin/env ruby

require 'duration'
require 'singleton'
require 'twitter'
require 'unicode_utils'
require_relative 'window'

class ColumnDefinitions

  COLUMNS = {
      SelectionColumn: 0,
      FlagsColumn: 4,
      UsernameColumn: 7,
      RelationsColumn: 24,
      TweetColumn: 26,
      EntitiesColumn: -12,
      TimeColumn: -7,
  }
  COLUMNS_BY_X = COLUMNS.to_a.sort do |lhs, rhs|
    lhs = lhs.last
    rhs = rhs.last
    (lhs<0) != (rhs<0) ? rhs <=> lhs : lhs <=> rhs
  end

end

class Column

  include HasPad

  attr_accessor :will_redraw
  attr_accessor :will_rerender

  def tick(time)
  end

  def draw
    if @will_redraw || @will_redraw == nil
      redraw
      @will_redraw = false
      @will_rerender = true
    end
    @will_rerender
  end

  def redraw
  end

  def render(*args)
    if @will_rerender
      rerender(*args)
      @will_rerender = false
    end
  end

  def rerender(x, y, w, h)
    return unless render_range.size > 0
    l = [ 0, render_range.min ].max
    r = [ render_range.max, w-1 ].min
    render_pad(l, 0, x+l, y, x+r, y+h-1) if r >= l
  end

  def flag_redraw(redraw = true)
    @will_redraw = redraw
  end

  def flag_rerender(rerender = true)
    @will_rerender = rerender
  end

  def render_range
    (0...width)
  end

end

class SelectionColumn < Column

  def initialize(tweetline)
    @tweetline = tweetline
    new_pad(3, 1)
  end

  def tick(time)
    if @tweetline.selected != @selected
      @selected = @tweetline.selected
      flag_redraw
    end
  end

  def redraw
    pad.erase
    if @selected
      pad.color(1,1,1,1, :bold)
      pad.write(0, 0, '  >')
    end
  end

  def render_range
    (0...3)
  end

end

class FlagsColumn < Column

  def initialize(tweetline)
    @tweetline = tweetline
    new_pad(2, 1)
  end

  def redraw
    pad.erase
    @f1 = false
    @f2 = false
    if @tweetline.own_tweet?
      if @tweetline.tweet.favorite_count > 0
        count = @tweetline.tweet.favorite_count
        @f1 = true
        pad.color(5,0,0)
        pad.write(0, 0, (count >= 10 ? '+' : count.to_s))
      elsif @tweetline.tweet.retweet_count > 0
        count = @tweetline.tweet.retweet_count
        @f2 = true
        pad.color(0,5,0)
        pad.write(1, 0, (count >= 10 ? '+' : count.to_s))
      end
    else
      if @tweetline.favorited?
        @f1 = true
        pad.color(5,0,0)
        pad.write(0, 0, 'L')
      elsif @tweetline.tweet.retweeted?
        @f2 = true
        pad.color(0,5,0)
        pad.write(1, 0, 'R')
      end
    end
  end

  def render_range
    ((@f1 ? 0 : 1) ... (@f2 ? 2 : 1))
  end

end

class UsernameColumn < Column

  def self.draw_username(pad, x, name, image)
    (0...name.length).each do |i|
      color = image.pixel_color(i,0)
      r,g,b = [ color.red, color.green, color.blue ]
      r,g,b = [r,g,b].map { |f| (((f/256.0/256.0)*0.89+0.11)*5).round }
      pad.color(r,g,b)
      pad.write(x+i, 0, name[i])
    end
  end

  attr_accessor :render_range

  def initialize(tweetline)
    @tweetline = tweetline
    new_pad(20, 1)
  end

  def redraw
    pad.erase
    name = "@#{@tweetline.tweet.user.screen_name}"
    profile_image = @tweetline.store.get_profile_image(@tweetline.tweet.user)
    UsernameColumn.draw_username(pad, 0, name, profile_image)
    @render_range = (0...name.length)
  end

end

class RelationsColumn < Column

  def initialize(tweetline)
    @tweetline = tweetline
    new_pad(1, 1)
  end

  def tick(time)
    if @tweetline.relations != @relation
      @relation = @tweetline.relations
      flag_redraw
    end
  end

  def redraw
    pad.erase
    case @relation
      when :same_user
        pad.color(4,4,1, :bold)
        pad.write(0, 0, '>')
      when :reply_tree_same_user
        pad.color(4,4,1, :bold, :reverse)
        pad.write(0, 0, '>')
      when :reply_tree_other_user
        pad.color(5,3,3, :bold, :reverse)
        pad.write(0, 0, '>')
    end
  end

  def render_range
    (0...1)
  end

end

class TweetColumn < Column

  class TrailerHelper

    include Singleton
    include HasPad

    TRAILER_WIDTH = 20

    def initialize
      new_pad(TRAILER_WIDTH, 1)
    end

    def redraw
      # Draw the gibberish text
      gibberish = (1...TRAILER_WIDTH).map{ (33+rand(94)).chr }.join
      gibberish[-4, 4] = '▒▒▒▓'
      pad.color(0,1,0,1)
      pad.write(0, 0, gibberish)

      # Draw the head
      pad.color(0,1,0,1, :reverse)
      pad.write(TRAILER_WIDTH-1, 0, ' ')
    end

  end

  class FakeEntity
    attr_reader :indices
    def initialize(indices)
      @indices = indices
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

  def initialize(tweetline)
    @tweetline = tweetline

    # Transform entities. We do this by making a sorted list of entities we care about, splitting
    # the tweet based on their indices, transforming the pieces that correspond to entities, and
    # rejoining all the pieces
    full_text = @tweetline.tweet.full_text

    entities = @tweetline.tweet.user_mentions + @tweetline.tweet.urls + @tweetline.tweet.media
    entities.sort! { |lhs, rhs| lhs.indices.first <=> rhs.indices.first }
    entities.uniq! { |e| e.indices.first }
    entities = [ FakeEntity.new([0]) ] + entities + [ FakeEntity.new([full_text.length]) ]
    if @tweetline.retweet?
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
        when Twitter::Media::AnimatedGif, Twitter::Media::Photo, Twitter::Media::Video, Twitter::Entity::URL
          slash_index = entity.display_url.index('/')
          tweet_pieces << TweetPiece.new(entity, :link_domain, entity.display_url[0...slash_index])
          tweet_pieces << TweetPiece.new(entity, :link_route, entity.display_url[slash_index..-1])
        else
          nil # Do nothing - the entity is discarded
      end
      tweet_pieces << TweetPiece.new(nil, :text, full_text[entity.indices.last...next_entity.indices.first])
    end
    if @tweetline.retweet?
      # See above; the first piece will be the text 'RT', second the @username
      tweet_pieces[0].type = :retweet_marker
      tweet_pieces[1].type = :retweet_username
    end
    tweet_pieces.each { |piece| piece.text = $htmlentities.decode(piece.text) }
    tweet_pieces = tweet_pieces.flat_map do |piece|
      # TODO: Combine consecutive newlines and tabs, filter out empty strings
      piece.text.split(/(\r\n|\r|\n|\t)/).map do |string|
        case string
          when "\r\n", "\r", "\n"
            TweetPiece.new(nil, :whitespace, '↵ ')
          when "\t"
            TweetPiece.new(nil, :whitespace, '⇥ ')
          else
            TweetPiece.new(piece.entity, piece.type, string)
        end
      end
    end

    @pieces = tweet_pieces
    @text_width = tweet_pieces.map { |piece| piece.text_width }.reduce(0, :+)
    @text_length = tweet_pieces.map { |piece| piece.text.length }.reduce(0, :+)
    @trailer_x = 0

    new_pad(@text_width, 1)
  end

  def tick(time)
    flag_rerender if @trailer_x-TrailerHelper::TRAILER_WIDTH < @text_width
    @trailer_x += time
  end

  def redraw
    pad.erase
    position = 0
    @pieces.each do |piece|
      case piece.type
        when :text
          if @tweetline.retweet?
            pad.color(3,5,3)
          elsif @tweetline.mention?
            pad.color(5,4,3)
          elsif @tweetline.own_tweet?
            pad.color(3,5,5)
          else
            pad.color(1,1,1,1)
          end
        when :link_domain
          pad.color(1,1,1,0)
        when :link_route
          pad.color(0,0,0,1)
        when :whitespace
          pad.color(0,0,0,1)
        when :retweet_marker
          pad.color(0,5,0)
        when :mention_username
          pad.color(4,3,2)
        when :retweet_username
          name = piece.text
          profile_image = @tweetline.store.get_profile_image(@tweetline.tweet.retweeted_tweet.user)
          UsernameColumn.draw_username(pad, position, name, profile_image)
      end
      pad.write(position, 0, piece.text) unless piece.type == :retweet_username
      position += piece.text_width
    end
  end

  def rerender(x, y, w, h)
    super(x, y, w, h)

    # Rendering the trailer messes things up if there are non-1-width characters
    if @text_width == @text_length
      dst_l = @trailer_x - TrailerHelper::TRAILER_WIDTH
      dst_r = @trailer_x
      src_x = [ 0, -1*dst_l ].max
      dst_l_capped = [ 0, dst_l ].max
      dst_r_capped = [ dst_r, w, @text_width ].min
      TrailerHelper.instance.redraw
      TrailerHelper.instance.render_pad(src_x, 0, x+dst_l_capped, y, x+dst_r_capped-1, y+h-1)
    end
  end

  def render_range
    w = [ 0, [ @trailer_x - TrailerHelper::TRAILER_WIDTH, @text_width ].min ].max
    (0...w)
  end

end

class EntitiesColumn < Column

  attr_accessor :render_range

  def initialize(tweetline)
    @tweetline = tweetline
    new_pad(3, 1)
    @render_range = (0...0)
  end

  def redraw
    pad.erase
    if @tweetline.tweet.media?
      @render_range = (0...3)
      pad.color(1,1,1,0, :bold)
      case @tweetline.tweet.media[0]
        when Twitter::Media::Photo
          if @tweetline.tweet.media.size == 1
            pad.write(0, 0, 'img')
          else
            pad.write(0, 0, "i:#{@tweetline.tweet.media.size.to_s}")
          end
        when Twitter::Media::Video
          pad.write(0, 0, 'vid');
        when Twitter::Media::AnimatedGif
          pad.write(0, 0, 'gif');
        else
          @render_range = (0...0)
      end
    end
  end

end

class TimeColumn < Column

  def initialize(tweetline)
    @tweetline = tweetline
    new_pad(3, 1)
  end

  def tick(time)
    duration = Duration.new(Time::now - @tweetline.tweet.created_at)
    timestring = # don't use strftime since it has really bad performance
      if duration.days > 0
        "#{duration.days}d"
      elsif duration.hours > 0
        "#{duration.hours}h"
      elsif duration.minutes > 0
        "#{duration.minutes}m"
      else
        "#{duration.seconds}s"
      end

    if timestring != @timestring
      hue = 40.0/60.0
      saturation = 0.0
      brightness = 1.0
      if duration.days > 0
        brightness = 0.5
      elsif duration.hours > 0
        saturation = 1.0 - (duration.hours-1)/23.0
        brightness = 1.0 - (duration.hours-1)/46.0
      elsif duration.minutes > 0
        hue = (30.0/60.0 - (duration.minutes/60.0 * 50.0/60.0)) % 1.0
        saturation = 1.0
      else
        hue = 30.0/60.0
        saturation = duration.seconds/60.0
      end

      @timestring = timestring
      @rgb = pad.hsv_to_color(hue, saturation, brightness)
      flag_redraw
    end
  end

  def redraw
    pad.erase
    pad.color(*@rgb)
    pad.write(0, 0, @timestring.rjust(3))
  end

  def render_range
    (0...3)
  end

end

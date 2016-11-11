#!/usr/bin/env ruby

require 'duration'
require 'singleton'
require 'twitter'
require 'unicode_utils'
require_relative 'tweetstore'
require_relative 'world/thing'
require_relative 'world/window'

module ColumnDefinitions

  COLUMNS = {
      SelectionColumn: 0,
      FlagsColumn: 4,
      UsernameColumn: 7,
      RelationsColumn: 24,
      TweetColumn: 26,
      EntitiesColumn: -9,
      TimeColumn: -4,
  }
  COLUMNS_BY_X = COLUMNS.to_a.sort do |lhs, rhs|
    lhs = lhs.last
    rhs = rhs.last
    (lhs<0) != (rhs<0) ? rhs <=> lhs : lhs <=> rhs
  end

end

class Column < Thing

  include HasPad
  include PadHelpers

  attr_accessor :max_size

  def initialize
    super
    size.y = 1
    @max_size = Coord.new
  end

  def column_name
    ''
  end

  def rerender
    bounded_size = Coord.new([ size.x, max_size.x ].min, size.y)
    rerender_pad(clip, bounded_size)
  end

end

class EmptyColumn < Column

  def initialize(_)
    super()
  end

  def rerender
  end

end

class SelectionColumn < Column

  def initialize(tweetline)
    super()
    @size = Coord.new(3, 1)
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

end

class FlagsColumn < Column

  def initialize(tweetline)
    super()
    @tweetline = tweetline
    new_pad(2, 1)
  end

  def tick(time)
    if @tweetline.favorited? != @favorited
      @favorited = @tweetline.favorited?
      flag_redraw
    end
    if @tweetline.tweet.retweeted? != @retweeted
      @retweeted = @tweetline.tweet.retweeted?
      flag_redraw
    end

    if @tweetline.tweet.favorite_count != @favorite_count
      @favorite_count = @tweetline.tweet.favorite_count
      flag_redraw
    end
    if @tweetline.tweet.retweet_count != @retweet_count
      @retweet_count = @tweetline.tweet.retweet_count
      flag_redraw
    end
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
    @size = Coord.new((@f1?1:0) + (@f2?1:0), 1)
    @clip = Coord.new(@f1 ? 0 : 1)
  end

end

class UsernameColumn < Column

  include ProfileImageWatcher

  def self.draw_username(pad, x, y, name, image, *style)
    if image
      (0...name.length).each do |i|
        color = image.pixel_color(i,0)
        r,g,b = [ color.red, color.green, color.blue ]
        r,g,b = [r,g,b].map { |f| (((f/256.0/256.0)*0.89+0.11)*5).round }
        pad.color(r,g,b, *style)
        pad.write(x+i, y, name[i])
      end
    else
      pad.color(0,0,0,1, *style)
      pad.write(x, y, name)
    end
  end

  def initialize(tweetline)
    super()
    @tweetline = tweetline
    new_pad(20, 1)
    watch_store(@tweetline.store)
  end

  def tick(time)
    flag_redraw if any_profile_image_changed?
  end

  def redraw
    pad.erase
    name = "@#{@tweetline.tweet.user.screen_name}"
    @profile_image = get_and_watch_profile_image(@tweetline.tweet.user)
    UsernameColumn.draw_username(pad, 0, 0, name, @profile_image)
    @size = Coord.new(name.length, 1)
  end

end

class RelationsColumn < Column

  def initialize(tweetline)
    super()
    @size = Coord.new(1, 1)
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

end

class TweetColumn < Column

  include ProfileImageWatcher

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

  def initialize(tweetline)
    super()
    @tweetline = tweetline
    @text_width = @tweetline.tweet_pieces.map { |piece| piece.text_width }.reduce(0, :+)
    @text_length = @tweetline.tweet_pieces.map { |piece| piece.text.length }.reduce(0, :+)
    @trailer_x = 0

    new_pad(@text_width, 1)
    watch_store(@tweetline.store)
  end

  def tick(time)
    flag_redraw if any_profile_image_changed?
    flag_rerender if @trailer_x-TrailerHelper::TRAILER_WIDTH < @text_width
    @trailer_x += time
  end

  def redraw
    pad.erase
    position = 0
    @tweetline.tweet_pieces.each do |piece|
      color_code = @tweetline.store.config.tweet_colors_column(piece.type)
      case color_code[0]
        when :none
          nil
        when :username
          name = piece.text
          profile_image = get_and_watch_profile_image(piece.entity)
          UsernameColumn.draw_username(pad, position, 0, name, profile_image, *color_code[1..-1])
          position += piece.text_width
        else
          pad.color(*color_code)
          pad.write(position, 0, piece.text)
          position += piece.text_width
      end
    end
  end

  def render
    if will_rerender
      w = [ 0, [ @trailer_x - TrailerHelper::TRAILER_WIDTH, @text_width ].min ].max
      @size = Coord.new(w, 1)
    end
    super
  end

  def rerender
    super

    # Rendering the trailer messes things up if there are non-1-width characters
    if @text_width == @text_length
      gpos = global_pos
      dst_l = @trailer_x - TrailerHelper::TRAILER_WIDTH
      dst_r = @trailer_x
      src_x = [ 0, -1*dst_l ].max
      dst_l_capped = [ 0, dst_l ].max
      dst_r_capped = [ dst_r, max_size.x, @text_width ].min
      TrailerHelper.instance.redraw
      TrailerHelper.instance.render_pad(src_x, 0, gpos.x+dst_l_capped, gpos.y, gpos.x+dst_r_capped-1, gpos.y)
    end
  end

end

class EntitiesColumn < Column

  def initialize(tweetline)
    super()
    @tweetline = tweetline
    new_pad(3, 1)
  end

  def redraw
    pad.erase
    if @tweetline.tweet.media?
      @size = Coord.new(3, 1)
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
          @size = Coord.new(0, 1)
      end
    end
  end

end

class TimeColumn < Column

  def initialize(tweetline)
    super()
    @size = Coord.new(3, 1)
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

end

class StreamingColumn < Column

  def initialize(tweetline)
    super()
    @size = Coord.new(20, 1)
    new_pad(20, 1)
    @time = 0
  end

  def tick(time)
    @time += time
    flag_redraw
  end

  def redraw
    pad.erase
    pad.color(0,0,0,1)
    pad.write(0, 0, 'Streaming...')
    pad.write(13, 0, %w[– \\ | /][(@time/3)%4])
  end

end

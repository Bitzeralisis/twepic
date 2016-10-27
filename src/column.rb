#!/usr/bin/env ruby

require 'duration'
require 'singleton'
require 'twitter'
require 'unicode_utils'
require_relative 'world/thing'
require_relative 'world/window'

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

class Column < Thing

  include HasPad

  def rerender(x, y, w, h)
    return unless render_range.size > 0
    l = [ 0, render_range.min ].max
    r = [ render_range.max, w-1 ].min
    render_pad(l, 0, x+l, y, x+r, y+h-1) if r >= l
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

  def tick(time)
    if @tweetline.favorited? != @favorited
      @favorited = @tweetline.favorited?
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
  end

  def render_range
    ((@f1 ? 0 : 1) ... (@f2 ? 2 : 1))
  end

end

class UsernameColumn < Column

  def self.draw_username(pad, x, y, name, image, *style)
    (0...name.length).each do |i|
      color = image.pixel_color(i,0)
      r,g,b = [ color.red, color.green, color.blue ]
      r,g,b = [r,g,b].map { |f| (((f/256.0/256.0)*0.89+0.11)*5).round }
      pad.color(r,g,b, *style)
      pad.write(x+i, y, name[i])
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
    UsernameColumn.draw_username(pad, 0, 0, name, profile_image)
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

  def initialize(tweetline)
    @tweetline = tweetline
    @text_width = @tweetline.tweet_pieces.map { |piece| piece.text_width }.reduce(0, :+)
    @text_length = @tweetline.tweet_pieces.map { |piece| piece.text.length }.reduce(0, :+)
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
    @tweetline.tweet_pieces.each do |piece|
      color_code = @tweetline.store.config.tweet_colors_column(piece.type)
      case color_code[0]
        when :none
          nil
        when :username
          name = piece.text
          profile_image = @tweetline.store.get_profile_image(piece.entity)
          UsernameColumn.draw_username(pad, position, 0, name, profile_image, *color_code[1..-1])
          position += piece.text_width
        else
          pad.color(*color_code)
          pad.write(position, 0, piece.text)
          position += piece.text_width
      end
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

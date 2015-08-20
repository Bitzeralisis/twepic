#!/usr/bin/env ruby

require 'twitter'
require 'unicode_utils'
require_relative 'world/world'

class TweetsPanel < Thing

  def initialize(clients)
    @clients = clients

    @mode = :timeline

    @tweets = []
    @prev_top = -1
    @selected = 0

    @post = ''

    @time = 0
  end

  def tick
    # Consume events from streaming
    until @clients.stream_queue.empty?
      event = @clients.stream_queue.pop
      case event
      when Twitter::Tweet
        @tweets << TweetLine.new(event)
      end
    end

    # Consume inputs
    while true
      input = @world.getch
      break if input == -1
      case @mode
      when :timeline
        timeline_consume_input(input)
      when :post
        post_consume_input(input)
      end
    end

    # Render
    render_timeline
    render_post

    @time += 1
  end

  START_Y = 3
  END_Y = -10

  def timeline_consume_input(input)
    case input
    when 'j'.ord
      @tweets[@selected].redraw = true
      @selected = [ @selected+1, @tweets.size-1 ].min
      @tweets[@selected].redraw = true
    when 'k'.ord
      @tweets[@selected].redraw = true
      @selected = [ 0, @selected-1 ].max
      @tweets[@selected].redraw = true
    when 't'.ord
      @mode = :post
    end
  end

  def render_timeline
    return if @tweets.size == 0

    @tweets.each { |t| t.tick }

    # Figure out which index is the topmost tweet to display
    num_tweets = @tweets.size
    height = @world.height - START_Y + END_Y
    top = @prev_top
    if @prev_top < 0
      top = 0
    end

    if @selected < top
      top = @selected
    elsif @selected >= top + height
      top = @selected - height + 1
    end

    # If top changed, then every tweet needs to be re-rendered
    redraw = false
    if @prev_top != top
      @world.clear
      @prev_top = top
      redraw = true
    end

    # Draw the top bar
    if redraw
      @world.color4(0,1,1,1)
      @world.invert
      @world.bold
      @world.write(0, 1, (1..@world.width).map{' '}.join)
      @world.write(5, 1, 'USER')
      @world.write(25, 1, 'TWEET')
    end

    # Draw all the tweets
    i = START_Y
    @tweets[top, height].each_index do |index|
      index += top
      tweet = @tweets[index]
      tweet.render_at(@world, i, index == @selected, redraw)
      i += 1
    end
  end

  POST_START_Y = -8

  def post_consume_input(input)
    case input

    # Esc
    when 27
      # Exit post mode
      @post = ''
      @mode = :timeline

    # Backspace
    when 127
      # Delete a character
      @post = @post[0..-2]

    # Return
    when "\r".ord
      # Post the tweet
      post_tweet(@post)
      @post = ''
      @mode = :timeline

    else
      # Every other input is just a character in the post
      @post += input.chr
    end
  end

  def render_post
    y = @world.height + POST_START_Y

    # Clear the post area
    @world.color(0)
    @world.write(0, y, ''.ljust(@world.width))
    @world.write(0, y+2, ''.ljust(@world.width))

    if @mode == :post
      # Render status bar
      glow = 0.5 + 0.5*Math.sin(@time/20.0)
      @world.color3((2*glow).round, (5*glow).round, (4*glow).round)
      @world.invert
      @world.write(0, y, ''.ljust(@world.width))

      @world.color3(2,5,4)
      @world.invert
      @world.bold
      @world.write(6, y, ' COMPOSE TWEET ')

      # Render the post
      @world.color4(1,1,1,1)
      @world.write(7, y+2, @post)
      @world.bold
      @world.write(3, y+2, '>')
    end
  end

  def post_tweet(text)
    @clients.rest_api.update(text)
  end

end

class TweetLine

  attr_writer :redraw

  def initialize(tweet)
    @tweet = tweet
    @text =
      '     ' +
      "@#{@tweet.user.screen_name}".ljust(20) +
      @tweet.full_text.gsub(/[\r\n\t]/, '  ')
    @text_width = UnicodeUtils.display_width(@text)
    @appear = TRAILER_START # X-position of the head of the trailer
    @appear_chars = 0 # Index into @text which is being rendered
    @redraw = false
  end

  def tick
    if @appear <= @text_width + TRAILER_WIDTH
      @appear += 1
      if UnicodeUtils.display_width(@text[0, @appear_chars]) < @appear-TRAILER_WIDTH
        @appear_chars += 1
      end
    end
  end

  def render_at(world, y, selected, redraw)
    redraw | @redraw ? render_redraw(world, y, selected) : render(world, y, selected)
  end

  private

  TRAILER_START = 5 # The starting left position of the trailer
  TRAILER_WIDTH = 20 # Total width of the trailer

  def render(world, y, selected)
    if @appear <= @text_width + TRAILER_WIDTH
      render_redraw(world, y, selected)
    end
  end

  def render_redraw(world, y, selected)
    # Draw the trailer
    right = @appear-1
    left = [ TRAILER_START, @appear-TRAILER_WIDTH ].max
    if right < @text_width
      # Draw the head of the traile
      world.color4(0,1,0,1)
      world.write(0, y, ' ')
    end
    if left < @text_width
      # Draw the gibberish text
      gibberish_begin = left
      gibberish_end = [ right, @text_width ].min
      gibberish_len = gibberish_end - gibberish_begin
      gibberish = (1...TRAILER_WIDTH).map{ (33+rand(94)).chr }.join
      gibberish[-4, 4] = '▒▒▒▓'
      gibberish = gibberish[0, gibberish_len]
      world.color4(0,1,0,1)
      world.write(gibberish_begin, y, gibberish)
    end

    # Draw text
    world.color4(1,1,1,1)
    world.write(0, y, @text[0, @appear_chars])

    # Draw selection arrow
    if selected
      world.color4(1,1,1,1)
      world.bold
      world.write(2, y, '>')
    end

    @redraw = false
  end

end

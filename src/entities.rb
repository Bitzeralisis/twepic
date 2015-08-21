#!/usr/bin/env ruby

require 'twitter'
require 'unicode_utils'
require_relative 'world'

class TweetsPanel < Thing

  def initialize(clients)
    @clients = clients

    @mode = :timeline

    @tweets = []
    @prev_top = -1
    @next_top = 0
    @selected = 0

    @post = ''
    @reply_to = nil

    @time = 0
  end

  def tick
    # Consume events from streaming
    until @clients.stream_queue.empty?
      event = @clients.stream_queue.pop
      case event
      when Twitter::Tweet
        # If the selection arrow is on the streaming spinner, then follow it
        @selected += 1 if @selected == @tweets.size
        # If we can scroll down one tweet without the selection arrow
        # disappearing, then do so, but only if the view is full
        @next_top += 1 if @selected > @next_top &&
          @next_top + @world.height - START_Y + END_Y - 1 == @tweets.size
        flags = []
        flags << :mention if event.full_text.include?("@#{@clients.user.screen_name}")
        flags << :self if event.user.id == @clients.user.id
        @tweets << TweetLine.new(event, flags)
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

    # Tick the tweet lines
    @tweets.each { |t| t.tick }

    @time += 1
  end

  def draw
    render_timeline
    render_post
  end

  START_Y = 3
  END_Y = -10

  def timeline_consume_input(input)
    case input
    when 'j'.ord
      @tweets[@selected].redraw = true if @tweets[@selected]
      @selected = [ @selected+1, @tweets.size ].min
      @tweets[@selected].redraw = true if @tweets[@selected]
    when 'k'.ord
      @tweets[@selected].redraw = true if @tweets[@selected]
      @selected = [ 0, @selected-1 ].max
      @tweets[@selected].redraw = true if @tweets[@selected]
    when 't'.ord
      @mode = :post
      @reply_to = nil
    when 'r'.ord
      return unless @tweets[@selected] # Do nothing when following stream
      @mode = :post
      @reply_to = @tweets[@selected].tweet
      @post = "@#{@reply_to.user.screen_name} "
    end
  end

  def render_timeline
    return if @tweets.size == 0

    # Figure out which index is the topmost tweet to display
    num_tweets = @tweets.size
    height = @world.height - START_Y + END_Y
    bottom = @world.height + END_Y
    top = @next_top

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
      @next_top = top
      redraw = true
    end

    # Draw the top bar
    if redraw
      @world.color4(0,1,1,1)
      @world.invert
      @world.bold
      @world.write(0, 1, (1..@world.width).map{' '}.join)
      @world.write(8, 1, 'USER')
      @world.write(28, 1, 'TWEET')
    end

    # Draw all the tweets
    i = START_Y
    @tweets[top, height].each_index do |index|
      index += top
      tweet = @tweets[index]
      tweet.render_at(@world, i, redraw)
      i += 1
    end

    # Draw the "streaming" spinner
    if i < bottom
      @world.color4(0,0,0,1)
      @world.write(2, i, ' ') # Clear the selection arrow
      @world.write(28, i, 'Streaming...')
      @world.write(41, i, ['–','\\','|','/'][(@time/3)%4])
    end

    # Draw selection arrow
    @world.color4(1,1,1,1)
    @world.bold
    @world.write(2, @selected-top+START_Y, '>')
  end

  POST_START_Y = -5

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
      post_tweet
      @post = ''
      @mode = :timeline

    else
      # Every other input is just a character in the post
      @post += input.chr(Encoding::UTF_8)
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
      r,g,b = @reply_to ? [5,4,2] : [2,4,5]
      glow = 0.75 + 0.25*Math.sin(@time/20.0)

      @world.color3((r*glow).round, (g*glow).round, (b*glow).round)
      @world.invert
      @world.write(0, y, ''.ljust(@world.width))

      @world.color3(r,g,b)
      @world.invert
      @world.bold
      @world.write(6, y, @reply_to ? ' COMPOSE REPLY ' : ' COMPOSE UPDATE ')

      # Render the post
      @world.color4(1,1,1,1)
      @world.write(7, y+2, @post)
      @world.bold
      @world.write(3, y+2, '>')
    end
  end

  def post_tweet
    # The first at-mention in the tweet must match the user being replied to,
    # otherwise don't count it as a reply
    # TODO Make it check the first at-mention, not just any at-mention
    if @reply_to && !@post.include?("@#{@reply_to.user.screen_name}")
      @reply_to = nil
    end

    if @reply_to
      @clients.rest_api.update(@post, in_reply_to_status: @reply_to)
    else
      @clients.rest_api.update(@post)
    end
  end

end

class TweetLine

  attr_reader :tweet
  attr_writer :redraw

  def initialize(tweet, flags)
    @tweet = tweet
    @flags = flags

    @text =
      '        ' +
      "@#{@tweet.user.screen_name}".ljust(20) +
      @tweet.full_text.gsub(/[\r\n\t]/, '  ')
    @text_width = UnicodeUtils.display_width(@text)
    @appear = TRAILER_START # X-position of the head of the trailer
    @appear_chars = 0 # Index into @text which is being rendered
    @redraw = true
  end

  def tick
    if @appear <= @text_width + TRAILER_WIDTH
      @appear += 1
      if UnicodeUtils.display_width(@text[0, @appear_chars]) < @appear-TRAILER_WIDTH
        @appear_chars += 1
      end
    end
  end

  def render_at(world, y, redraw)
    redraw | @redraw ? render_redraw(world, y) : render(world, y)
  end

  private

  TRAILER_START = 7 # The starting left position of the trailer
  TRAILER_WIDTH = 20 # Total width of the trailer

  def render(world, y)
    if @appear <= @text_width + TRAILER_WIDTH
      render_redraw(world, y)
    end
  end

  def render_redraw(world, y)
    # Clear the line
    world.color(0)
    world.write(0, y, ''.ljust(world.width))

    # Draw the trailer
    right = @appear-1
    left = [ TRAILER_START, @appear-TRAILER_WIDTH ].max
    if right < @text_width
      # Draw the head of the trailer
      world.color4(0,1,0,1)
      world.invert
      world.write(right, y, ' ')
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

    # Draw flags
    if @flags.include?(:self)
      world.color3(4,5,5)
      world.write(5, y, "S")
    elsif @flags.include?(:mention)
      world.color3(5,3,1)
      world.bold
      world.write(5, y, "M")
    end

    @redraw = false
  end

end

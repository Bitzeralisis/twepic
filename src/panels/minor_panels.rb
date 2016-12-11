require 'twitter'
require_relative 'panel'
require_relative '../world/window'

class NoticePanel < Panel

  include HasPad
  include PadHelpers

  FADE_TIME = 60

  def initialize(detail_panel)
    super()
    @detail_panel = detail_panel
    self.size = screen_width, 1

    @text = ''
    @color = [0]
    @start_time = -2*FADE_TIME
    @time = 0
  end

  def set_notice(text, *color)
    @text = text
    @color = color
    @start_time = @time
  end

  def tick(time)
    flag_redraw if @time <= @start_time+FADE_TIME
    @time += time
  end

  def redraw
    pad.erase

    t = (@time - @start_time).to_f / FADE_TIME
    col = @color.map { |c| ((1.0-t)*c).round }
    pos = (size.x-@text.length)/2

    pad.color(*col)
    pad.write(pos-4, 0, "░▒▓ #{''.ljust(@text.length)} ▓▒░")

    pad.color(*col, :bold, :reverse)
    pad.write(pos-1, 0, " #{@text} ")
  end

  def rerender
    return if @time >= @start_time+FADE_TIME
    rerender_pad(Coord.new((size.x-@text.length)/2 - 5, 0), Coord.new(@text.length+10, 1))
  end

  def flag_rerender(rerender = true)
    super
    @detail_panel.flag_rerender(rerender)
  end

  def on_resize(old_size, new_size)
    return if old_size == new_size
    new_pad(new_size)
  end

end

class EventsPanel < Panel

  module Event
    attr_accessor :event, :display, :size, :x, :stopped, :decay
  end

  class OutEvent
    include Event
    def initialize(rest, display)
      @event = rest
      @display = display
      @size = @display[0].length + PADDING
      @x = 0
      @stopped = false
      @decay = 0
    end
  end

  class InEvent
    include Event
    def initialize(event_type, display, right)
      @event = event_type
      @display = display
      @size = @display[0].length + PADDING
      @x = right
      @stopped = false
      @decay = 0
    end
  end

  class FakeEvent
    include Event
    def initialize(x = 0)
      @event = nil
      @display = ['', 0]
      @size = 0
      @x = x
      @stopped = true
      @decay = 0
    end
    def decay=
    end
  end

  include HasPad
  include PadHelpers

  PADDING = 1
  SPEED_FACTOR = 0.1
  SPEED = 1

  def initialize(clients, config)
    super()
    @clients = clients
    @config = config
    @events_out = { rhs: FakeEvent.new }
    @events_in = [ FakeEvent.new(-10) ]
    self.size = screen_width, 2
  end

  def add_incoming_event(streaming_event)
    type =
        case streaming_event
          when Twitter::Tweet
            # TODO: Detect reply
            :tweet
          when Twitter::Streaming::DeletedTweet
            :delete
          when Twitter::Streaming::Event
            streaming_event.name
          else
            :nil
        end
    display = @config.event_in_display(type)
    if display
      @events_in << InEvent.new(type, display, size.x)
      flag_redraw
    end
  end

  def tick(time)
    # Add new outgoing events
    old_size = @events_out.size
    @clients.outgoing_requests.each do |r|
      @events_out[r] = OutEvent.new(r, @config.event_out_display(r.name)) unless @events_out[r]
    end
    flag_redraw if old_size != @events_out.size

    # Move events
    ([:rhs] + @clients.outgoing_requests).each_cons(2) do |rhs, lhs|
      left = @events_out[lhs]
      right = @events_out[rhs]
      if !left.stopped
        x_old = left.x
        # Move the left event right by SPEED_FACTOR of the distance to the right event
        left.x += (SPEED_FACTOR*(right.x-left.size-left.x)).ceil
        # Make sure events don't overlap
        left.x = [ left.x, right.x-left.size ].min
        left.stopped = true if left.x == x_old
      elsif [ :success, :failure ].include?(left.event.status)
        left.decay += 1
      end
    end

    @events_in.each_cons(2) do |left, right|
      # Move right event left by SPEED
      right.x -= SPEED
      # Make sure events don't overlap
      right.x = [ left.x+left.size, right.x ].max
    end

    flag_redraw if @events_out.size > 1 or @events_in.size > 1

    # Delete decayed events
    old_sizes = [ @events_out.size, @events_in.size ]
    @clients.outgoing_requests.delete_if { |r| @events_out[r].decay >= 30 }
    @events_out.delete_if { |_, e| e.decay >= 30 }
    @events_in.delete_if.with_index { |e, i| i > 0 && e.x + e.size < 0 }
    flag_redraw if old_sizes != [ @events_out.size, @events_in.size ]
  end

  def redraw
    pad.erase

    @events_out.each_value do |e|
      if e.event and e.x >= 0
        name = e.display[0]
        color = e.display[1..-1]
        if e.stopped
          if e.event.status == :success and e.decay > 15
            pad.color(0, (5.0*(30-e.decay)/15.0).round, 0)
            gibberish = (1..name.length).map{ (33+rand(15)).chr }.join
            pad.write(e.x, 0, gibberish)
          elsif e.event.status == :failure
            pad.color(4,0,0, :bold)
            pad.write(e.x, 0, name)
          else
            pad.color(*color)
            pad.write(e.x, 0, name)
          end
        else
          pad.color(*color)
          pad.write(e.x, 0, name)
        end
      end
    end

    @events_in.each do |e|
      if e.x >= 0
        name = e.display[0]
        color = e.display[1..-1]
        pad.color(*color)
        pad.write(e.x, 1, name)
      end
    end

    pad.color(0,0,0,1)
    pad.write(0, 0, 'OUT > ')
    pad.write(0, 1, '<<<<< ')
    pad.write(size.x-6, 0, ' >>>>>')
    pad.write(size.x-6, 1, ' < IN ')
  end

  def rerender
    rerender_pad
  end

  def on_resize(old_size, new_size)
    return if old_size == new_size
    @events_out[:rhs].x = new_size.x-5
    new_pad(new_size)
    flag_redraw
  end

end

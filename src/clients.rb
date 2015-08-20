#!/usr/bin/env ruby

require 'thread'

class TwitterClients

  attr_reader :rest_api, :stream_queue

  def initialize(rest_api, stream_api)
    @rest_api = rest_api
    @stream_api = stream_api
    @stream_queue = Queue.new
  end

  def start_streaming
    @rest_api.home_timeline.reverse.each { |t| @stream_queue << t }
    Thread.new do
      while true
        @stream_api.user { |o| @stream_queue << o }
      end
    end
  end

end

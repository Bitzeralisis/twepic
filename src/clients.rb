#!/usr/bin/env ruby

require 'thread'

class TwitterClients

  attr_reader :rest_api, :stream_queue
  attr_reader :user

  def initialize(rest_api, stream_api)
    @rest_api = rest_api
    @stream_api = stream_api
    @stream_queue = Queue.new
    @user = @rest_api.current_user
  end

  def start_streaming
    tweets = []
    tweets += @rest_api.home_timeline
    tweets += @rest_api.mentions_timeline
    tweets.sort! { |l, r| l.id - r.id }
    tweets.uniq! { |o| o.id }
    tweets.each { |t| @stream_queue << t }
    Thread.new do
      while true
        @stream_api.user { |o| @stream_queue << o }
      end
    end
  end

  def rest_concurrently(*args, &block)
    block.(@rest_api, args)
  end

end

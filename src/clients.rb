#!/usr/bin/env ruby

require 'thread'

class TwitterClients

  attr_reader :outgoing_requests
  attr_reader :rest_api
  attr_reader :stream_queue
  attr_reader :user

  def initialize(rest_api, stream_api)
    @rest_api = rest_api
    @stream_api = stream_api
    @stream_queue = Queue.new
    @user = @rest_api.current_user
    @outgoing_requests = []
  end

  def start_streaming
    tweets = []
    tweets += @rest_api.home_timeline(tweet_mode: 'extended')
    tweets += @rest_api.mentions_timeline(tweet_mode: 'extended')
    tweets.sort! { |l, r| l.id - r.id }
    tweets.uniq! { |o| o.id }
    tweets.each { |t| @stream_queue << t }
    Thread.new do
      while true
        @stream_api.user { |o| @stream_queue << o }
      end
    end
  end

  def rest_concurrently(name, *args)
    @outgoing_requests << RestConcurrent.new(name, @rest_api) { |api| yield(api, *args) }
  end

end

class RestConcurrent

  attr_reader :name
  attr_reader :status
  attr_reader :result

  def initialize(name, api)
    @name = name
    @status = :queued
    @thread = Thread.new { worker(api) { |api| yield(api) } }
  end

  def worker(rest_api)
    begin
      @status = :started
      @result = yield(rest_api)
      @status = :success
    rescue Exception => e
      @result = e
      @status = :failure
      $logger.error(e)
    end
  end

end

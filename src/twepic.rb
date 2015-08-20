#!/usr/bin/env ruby

require 'twitter'
require_relative 'config'
require_relative 'clients'
require_relative 'entities'
require_relative 'world/world'

def set_config(config)
  config.consumer_key = TwepicRc::CONSUMER_KEY
  config.consumer_secret = TwepicRc::CONSUMER_SECRET
  config.access_token = TwepicRc::ACCESS_TOKEN
  config.access_token_secret = TwepicRc::ACCESS_TOKEN_SECRET
end

def main
  rest = Twitter::REST::Client.new { |c| set_config(c) }
  stream = Twitter::Streaming::Client.new { |c| set_config(c) }
  clients = TwitterClients.new(rest, stream)
  panel = TweetsPanel.new(clients)

  world = World.new()
  world.add(panel)
  clients.start_streaming

  world.run
end

main

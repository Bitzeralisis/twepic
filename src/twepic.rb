#!/usr/bin/env ruby

require 'htmlentities'
require 'logger'
require 'twitter'
require 'twitter_oauth'
require_relative 'auth'
require_relative 'config'
require_relative 'clients'
require_relative 'panels'
require_relative 'world/world'

module TwepicRc

  class << self

    def authorization_flow
      puts 'Authenticating application...'

      begin
        consumer_token = get_consumer_token
        oauth = TwitterOAuth::Client.new(consumer_token)
        request_token = oauth.request_token(oauth_callback: 'oob')
        url = request_token.authorize_url
      rescue Exception => e
        puts 'Failed to authenticate application! Please check for updates to twepic.'
        raise e
      end

      puts 'Please open the following URL and enter the provided PIN.'
      puts "    #{url}"
      print 'Enter PIN: '
      pin = gets

      begin
        access_token = oauth.authorize(request_token.token, request_token.secret, oauth_verifier: pin)
        {
          token: access_token.token,
          secret: access_token.secret
        }
      rescue Exception => e
        puts 'Failed to authorize user! Are you sure you entered the PIN correctly?'
        raise e
      end
    end

    def make_clients
      consumer_token = get_consumer_token
      access_token = get_access_token
      unless access_token
        puts 'No user logged in.'
        access_token = authorization_flow
        save_access_token(access_token)
      end

      begin
        rest = Twitter::REST::Client.new { |c| set_config(c, consumer_token, access_token) }
        stream = Twitter::Streaming::Client.new { |c| set_config(c, consumer_token, access_token) }
        TwitterClients.new(rest, stream)
      rescue
        puts 'Failed to authorize user. Please log in again.'
        delete_access_token
        make_clients
      end
    end

  end

end

def main
  $logger = Logger.new('log.log')
  $htmlentities = HTMLEntities.new

  clients = TwepicRc::make_clients

  world = World.new
  world.run do
    panel = PanelSet.new(clients, Config.new)
    world << panel
    clients.start_streaming
  end
end

main

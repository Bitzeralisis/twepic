#!/usr/bin/env ruby

module TwepicRc

  class << self

    def set_config(config, consumer_token, access_token)
      config.consumer_key = consumer_token[:consumer_key]
      config.consumer_secret = consumer_token[:consumer_secret]
      config.access_token = access_token[:token]
      config.access_token_secret = access_token[:secret]
    end

    def get_consumer_token
      {
        consumer_key: CONSUMER_KEY,
        consumer_secret: decrypt(CONSUMER_SECRET)
      }
    end

    def get_access_token
      begin
        f = File.open(twepic_dir_token, 'rt')
        type = f.readline.strip
        token = f.readline.strip
        secret = f.readline.strip
        f.close
        return false if type != 'tokenformat0'
        {
            token: token,
            secret: decrypt(secret)
        }
      rescue
        false
      end
    end

    def save_access_token(token)
      begin
        Dir.mkdir(twepic_dir) unless Dir.exist?(twepic_dir)
        File.open(twepic_dir_token, 'wt') do |f|
          f.puts 'tokenformat0'
          f.puts token[:token]
          f.puts encrypt(token[:secret])
        end
      rescue Exception => e
        raise e
      end
    end

    def delete_access_token
      File.delete(twepic_dir_token) if File.exist?(twepic_dir_token)
    end

    private

    CONSUMER_KEY = '14La0c5tHz1EF8VkOkC8Ig80P'
    CONSUMER_SECRET = 'cCwEICCeYf1rQykrmYCV1wGVfEyJ2eyVIJHoH29lvB1OjZDoik'

    def encrypt(key)
      key.reverse.swapcase
    end

    def decrypt(key)
      key.reverse.swapcase
    end

    def twepic_dir
      Dir.home + '/.twepic'
    end

    def twepic_dir_token
      Dir.home + '/.twepic/token'
    end

  end

end

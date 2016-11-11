#!/usr/bin/env ruby

class Config

  def initialize
    @config = {
      tweet_colors_default: {
        hashtag:          [3,3,5],
        link_domain:      [1,1,1,0],
        link_route:       [0,0,0,1],
        mention_username: [:username],
        retweet_marker:   [0,5,0],
        retweet_username: [:username],
        text_mention:     [5,4,3],
        text_normal:      [1,1,1,1],
        text_not_friend:  [0,0,5],
        text_own_tweet:   [3,5,5],
        text_retweet:     [3,5,3],
        whitespace:       [0,0,0,1],
      },

      tweet_colors_column: {},

      tweet_colors_detail: {
        hashtag:          [3,3,5, :underline],
        link_domain:      [1,1,1,1, :underline],
        link_route:       [1,1,1,1, :underline],
        mention_username: [:username, :underline],
        retweet_marker:   [:none],
        retweet_username: [:none],
        text_mention:     [1,1,1,1],
        text_normal:      [1,1,1,1],
        text_not_friend:  [1,1,1,1],
        text_own_tweet:   [1,1,1,1],
        text_retweet:     [1,1,1,1],
        whitespace:       [:whitespace, 0,0,0,1],
      },
    }
  end

  def tweet_colors_column(key)
    @config[:tweet_colors_column][key] || @config[:tweet_colors_default][key]
  end

  def tweet_colors_detail(key)
    @config[:tweet_colors_detail][key] || @config[:tweet_colors_default][key]
  end

end

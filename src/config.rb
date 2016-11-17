#!/usr/bin/env ruby

module ColumnDefinitions

  COLUMNS = {
      SelectionColumn: 0,
      FlagsColumn: 4,
      UsernameColumn: 7,
      RelationsColumn: 24,
      TweetColumn: 26,
      EntitiesColumn: -9,
      TimeColumn: -4,
  }
  COLUMNS_BY_X = COLUMNS.to_a.sort do |lhs, rhs|
    lhs = lhs.last
    rhs = rhs.last
    (lhs<0) != (rhs<0) ? rhs <=> lhs : lhs <=> rhs
  end

end

class Config

  def initialize
    @config = {
      keybinds: {
          'zt' => :scroll_cursor_to_top,
          'zz' => :scroll_cursor_to_middle,
          'zb' => :scroll_cursor_to_bottom,

          'k' => :select_cursor_up,
          :up_arrow => :select_cursor_up,
          'j' => :select_cursor_down,
          :down_arrow => :select_cursor_down,
          'H' => :select_top_line,
          'M' => :select_middle_line,
          'L' => :select_bottom_line,
          'g' => :select_first_line,
          'G' => :select_last_line,
          'h' => :select_previous_related_line,
          :left_arrow => :select_previous_related_line,
          'l' => :select_next_related_line,
          :right_arrow => :select_next_related_line,

          'f' => :favorite,
          'F' => :unfavorite,
          't' => :compose_tweet,
          'r' => :compose_reply,
          'R' => :compose_reply_to_all,
          'e' => :retweet,
          'd' => :delete,

          'Q' => :quit,
      },

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

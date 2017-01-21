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
            PanelSet: {
              ' '.ord => :select_current_selection,
              'k'.ord => :select_cursor_up,
               3      => :select_cursor_up,
              'j'.ord => :select_cursor_down,
               2      => :select_cursor_down,
              'H'.ord => :select_top_line,
              'M'.ord => :select_middle_line,
              'L'.ord => :select_bottom_line,
              'g'.ord => :select_first_line,
              'G'.ord => :select_last_line,
              'h'.ord => :select_previous_related_line,
               4      => :select_previous_related_line,
              'l'.ord => :select_next_related_line,
               5      => :select_next_related_line,

              'z'.ord => {
                  't'.ord => :scroll_cursor_to_top,
                  'z'.ord => :scroll_cursor_to_middle,
                  'b'.ord => :scroll_cursor_to_bottom,
              },

              't'.ord => :compose_tweet,
              'r'.ord => :compose_selection_reply,
              'R'.ord => :compose_selection_reply_to_all,
              'f'.ord => :selection_favorite,
              'F'.ord => :selection_unfavorite,
              'e'.ord => :selection_retweet,
              'd'.ord => :selection_delete,
              'y'.ord => :selection_copy_text,
              'Y'.ord => :selection_copy_link,
              'O'.ord => :selection_open_link_external,

              'J'.ord => :tab_select_left,
              'K'.ord => :tab_select_right,
              'w'.ord => :tab_delete,
              'u'.ord => :selection_new_tab_user_tweets,
              'o'.ord => :selection_new_tab_related_tweets,

              9       => :detail_panel_mode,
              'Q'.ord => :quit,
            },

            DetailPanel: {
              'h'.ord => :select_previous_entity,
              4       => :select_previous_entity,
              'l'.ord => :select_next_entity,
              5       => :select_next_entity,

              'y'.ord => :selection_copy_text,
              'Y'.ord => :selection_copy_link,
              'O'.ord => :selection_open_link_external,

              9       => :timeline_mode,
              27      => :timeline_mode,
            },
        },

        event_in_display: {
            nil:        ['', 0],
            tweet:      ['T', 0,0,0,1],
            reply:      ['R', 5,4,3, :bold],
            favorite:   ['L', 5,0,0, :bold],
            unfavorite: ['L', 0,0,0,1],
            retweet:    ['R', 3,5,3, :bold],
            delete:     ['',  0],
            follow:     ['FOLLOW', 5,0,5, :bold],
            unfollow:   ['', 0],
        },

        event_out_display: {
            nil:        ['', 0],
            tweet:      ['TWEET',  3,5,5],
            reply:      ['REPLY',  5,4,3],
            favorite:   ['LIKE',   5,3,3],
            unfavorite: ['UNLIKE', 3,3,3],
            retweet:    [' RT ',   3,5,3],
            delete:     ['DELETE', 5,0,0],
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

  def event_in_display(key)
    @config[:event_in_display][key]
  end

  def event_out_display(key)
    @config[:event_out_display][key]
  end

  def keybinds(clazz)
    @config[:keybinds][clazz.to_s.to_sym]
  end

  def tweet_colors_column(key)
    @config[:tweet_colors_column][key] || @config[:tweet_colors_default][key]
  end

  def tweet_colors_detail(key)
    @config[:tweet_colors_detail][key] || @config[:tweet_colors_default][key]
  end

end

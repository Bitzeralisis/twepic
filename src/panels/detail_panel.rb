require_relative 'panel'
require_relative '../config'
require_relative '../tweetstore'
require_relative '../world/window'

class DetailPanel < Panel

  include HasPad
  include PadHelpers
  include ProfileImageWatcher

  attr_accessor :tweetline

  def initialize(config, tweetstore)
    super()
    self.size = screen_width, 9
    @config = config
    @tweetstore = tweetstore
    watch_store(tweetstore)
  end

  def tick(time)
    if @tweetline != @prev_tweetline
      @prev_tweetline = @tweetline
      if @tweetline.is_tweet?
        @linking_tweet_pieces = @tweetline.tweet_pieces.select { |piece| [ :mention_username, :hashtag, :link_domain ].include? piece.type }
        @selected_entity_index = 0
      end
      flag_redraw
    end
    flag_redraw if any_profile_image_changed?
  end

  def redraw
    pad.erase
    stop_watching_all_profile_images

    unless @tweetline.is_tweet?
      draw_at(false, @focused ? [ 1,1,1,1 ] : [ 0,0,0,1 ])
      return
    end

    bar_color =
        if @focused
          @tweetline.retweet? ? [ 0,4,0 ] : [ 0,1,1,1 ]
        else
          [ 0,0,0,1 ]
        end

    reply = nil
    if @tweetline.tweet.reply?
      reply = @tweetstore.fetch(@tweetline.tweet.in_reply_to_status_id)
      if reply
        draw_at(@tweetline.underlying_tweet, bar_color, (0..4))
        draw_at(reply, @focused ? [ 3,2,1 ] : [ 0,0,0,1 ], (6...size.y))
        pad.color(5,4,2, :bold)
        pad.write((size.x-7)/2, 6, ' ^ ^ ^ ')
      end
    end
    draw_at(@tweetline.underlying_tweet, bar_color) unless reply
  end

  def draw_at(ttweet, bar_color, yRange = (0...size.y))
    y = yRange.first

    # Draw the infobar
    pad.color(*bar_color, :reverse)
    pad.write(0, y, ''.ljust(size.x))

    unless ttweet
      text = ' NO TWEET SELECTED '
      xPos = (size.x - text.size) / 2
      pad.color(*bar_color, :reverse)
      pad.write(xPos, y, text)
      return
    end

    if ttweet.retweet?
      xPos = ColumnDefinitions::COLUMNS[:UsernameColumn]
      name = "@#{ttweet.tweet.retweeted_status.user.screen_name}"
      profile_image = get_and_watch_profile_image(ttweet.tweet.retweeted_status.user)
      UsernameColumn.draw_username(pad, xPos, y, name, profile_image, :bold)
      pad.color(0)
      pad.write(xPos-1, y, ' ')
      xPos += name.length

      pad.color(0,5,0, :bold)
      pad.write(xPos, y, ' << ')
      xPos += 4

      name = "@#{ttweet.tweet.user.screen_name}"
      profile_image = get_and_watch_profile_image(ttweet.tweet.user)
      UsernameColumn.draw_username(pad, xPos, y, name, profile_image, :bold)
      pad.color(0)
      pad.write(xPos+name.length, y, ' ')
    else
      name = "@#{ttweet.tweet.user.screen_name}"
      profile_image = get_and_watch_profile_image(ttweet.tweet.user)
      pad.color(0)
      pad.write(ColumnDefinitions::COLUMNS[:UsernameColumn]-1, y, ''.ljust(name.length+2))
      UsernameColumn.draw_username(pad, ColumnDefinitions::COLUMNS[:UsernameColumn], y, name, profile_image, :bold)
    end

    favs = 5,0,0, ttweet.root_twepic_tweet.favorites == 0 ? '' : " ♥ #{ttweet.root_twepic_tweet.favorites} "
    rts = 0,5,0, ttweet.root_tweet.retweet_count == 0 ? '' : " ⟳ #{ttweet.root_tweet.retweet_count} "
    time = 1,1,1,1, ttweet.root_tweet.created_at.getlocal.strftime(' %Y-%m-%d %H:%M:%S ')
    source = 1,1,1,1, " #{ttweet.root_tweet.source.gsub(/<.*?>/, '')} "
    place = 1,1,1,0, ttweet.root_tweet.place.nil? ? '' : " ⌖ #{ttweet.tweet.place.name} "
    xPos = size.x
    [ favs, rts, time, source, place ].reverse_each do |text|
      string = text.last
      color = text[0..-2]
      next if string.empty?
      xPos -= UnicodeUtils.display_width(string)+1
      pad.color(*color)
      pad.write(xPos, y, string)
    end

    xPos = ColumnDefinitions::COLUMNS[:UsernameColumn]
    yPos = y+2

    ttweet.tweet_pieces.each do |piece|
      break unless yRange === yPos
      if @focused and !@linking_tweet_pieces.empty? and
          @linking_tweet_pieces[@selected_entity_index].grouped_with.include?(piece)
        pad.color(1,1,1,1, :bold, :reverse)
        pad.write(xPos, yPos, piece.text)
        xPos += piece.text_width
      else
        color_code = @config.tweet_colors_detail(piece.type)
        case color_code[0]
          when :none
            nil
          when :username
            name = piece.text
            profile_image = get_and_watch_profile_image(piece.entity)
            UsernameColumn.draw_username(pad, xPos, yPos, name, profile_image, *color_code[1..-1])
            xPos += piece.text_width
          when :whitespace
            pad.color(*color_code[1..-1])
            if piece.entity.data == :tab
              xPos += 2
            end
            pad.write(xPos, yPos, piece.text)
            if piece.entity.data == :newline
              xPos = ColumnDefinitions::COLUMNS[:UsernameColumn]
              yPos += 1
            end
          else
            pad.color(*color_code)
            pad.write(xPos, yPos, piece.text)
            xPos += piece.text_width
        end
      end
    end
  end

  def rerender
    rerender_pad
  end

  def on_resize(old_size, new_size)
    return if old_size.x == new_size.x
    new_pad(new_size.x+1, 10)
    flag_redraw
  end

  private

  def action_select_previous_entity
    @selected_entity_index = @selected_entity_index <= 0 ? @linking_tweet_pieces.size-1 : @selected_entity_index-1
    flag_redraw
  end

  def action_select_next_entity
    @selected_entity_index = @selected_entity_index >= @linking_tweet_pieces.size-1 ? 0 : @selected_entity_index+1
    flag_redraw
  end

  def action_selection_copy_text
    selected_piece = @linking_tweet_pieces[@selected_entity_index]
    if selected_piece
      case selected_piece.type
        when :mention_username
          Clipboard.copy("@#{selected_piece.entity.screen_name}")
          @parent.set_notice('COPIED USERNAME', 5,5,5)
        when :hashtag
          Clipboard.copy("\##{selected_piece.entity.text}")
          @parent.set_notice('COPIED HASHTAG', 5,5,5)
        when :link_domain
          Clipboard.copy(selected_piece.entity.url)
          @parent.set_notice('COPIED LINK', 5,5,5)
      end
    end
  end

  def action_selection_copy_link
    selected_piece = @linking_tweet_pieces[@selected_entity_index]
    if selected_piece
      case selected_piece.type
        when :mention_username
          Clipboard.copy("https://twitter.com/#{selected_piece.entity.screen_name}")
          @parent.set_notice('COPIED LINK TO USER', 5,5,5)
        when :hashtag
          Clipboard.copy(selected_piece.entity.text)
          @parent.set_notice('COPIED HASHTAG TEXT', 5,5,5)
        when :link_domain
          Clipboard.copy(selected_piece.entity.expanded_url)
          @parent.set_notice('COPIED FULL LINK', 5,5,5)
      end
    end
  end

  def action_selection_open_link_external
    selected_piece = @linking_tweet_pieces[@selected_entity_index]
    if selected_piece
      case selected_piece.type
        when :mention_username
          Launchy.open("https://twitter.com/#{selected_piece.entity.screen_name}")
          @parent.set_notice('OPENING USER IN BROWSER...', 5,5,5)
        when :link_domain
          Launchy.open(selected_piece.entity.expanded_url)
          @parent.set_notice('OPENING LINK IN BROWSER...', 5,5,5)
      end
    end
  end

  def action_timeline_mode
    @parent.switch_mode(:timeline)
  end

end

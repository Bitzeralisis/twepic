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

  def consume_input(input)
    case input
      when 9, 27 # Tab, Esc
        @parent.switch_mode(:timeline)
      when 'h'.ord, 4 # Left
        @selected_entity_index = @selected_entity_index <= 0 ? @linking_tweet_pieces.size-1 : @selected_entity_index-1
        flag_redraw
      when 'l'.ord, 5 # Right
        @selected_entity_index = @selected_entity_index >= @linking_tweet_pieces.size-1 ? 0 : @selected_entity_index+1
        flag_redraw
      when 'y'.ord
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
        else
          return false
        end
      when 'Y'.ord
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
        else
          return false
        end
      when 'O'.ord
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
        else
          return false
        end
      else
        return false
    end
    true
  end

  def redraw
    pad.erase
    stop_watching_all_profile_images

    # Draw the infobar
    color = @focused ? [ 0,1,1,1, :reverse ] : [ 0,0,0,1, :reverse ]
    pad.color(*color, :bold)
    pad.write(0, 0, ''.ljust(size.x))

    unless @tweetline.is_tweet?
      text = ' NO TWEET SELECTED '
      xPos = (size.x - text.size) / 2
      pad.color(*color)
      pad.write(xPos, 0, text)
      return
    end

    if @tweetline.retweet?
      xPos = ColumnDefinitions::COLUMNS[:UsernameColumn]
      name = "@#{@tweetline.tweet.retweeted_status.user.screen_name}"
      profile_image = get_and_watch_profile_image(@tweetline.tweet.retweeted_status.user)
      UsernameColumn.draw_username(pad, xPos, 0, name, profile_image, :bold)
      pad.color(0)
      pad.write(xPos-1, 0, ' ')
      xPos += name.length

      pad.color(0,5,0, :bold)
      pad.write(xPos, 0, ' << ')
      xPos += 4

      name = "@#{@tweetline.tweet.user.screen_name}"
      profile_image = get_and_watch_profile_image(@tweetline.tweet.user)
      UsernameColumn.draw_username(pad, xPos, 0, name, profile_image, :bold)
      pad.color(0)
      pad.write(xPos+name.length, 0, ' ')
    else
      name = "@#{@tweetline.tweet.user.screen_name}"
      profile_image = get_and_watch_profile_image(@tweetline.tweet.user)
      pad.color(0)
      pad.write(ColumnDefinitions::COLUMNS[:UsernameColumn]-1, 0, ''.ljust(name.length+2))
      UsernameColumn.draw_username(pad, ColumnDefinitions::COLUMNS[:UsernameColumn], 0, name, profile_image, :bold)
    end

    favs = 5,0,0, @tweetline.root_tweet.favorite_count == 0 ? '' : " ♥ #{@tweetline.root_tweet.favorite_count} "
    rts = 0,5,0, @tweetline.root_tweet.retweet_count == 0 ? '' : " ⟳ #{@tweetline.root_tweet.retweet_count} "
    time = 1,1,1,1, @tweetline.root_tweet.created_at.getlocal.strftime(' %Y-%m-%d %H:%M:%S ')
    source = 1,1,1,1, " #{@tweetline.root_tweet.source.gsub(/<.*?>/, '')} "
    place = 1,1,1,0, @tweetline.root_tweet.place.nil? ? '' : " ⌖ #{@tweetline.tweet.place.name} "
    xPos = size.x
    [ favs, rts, time, source, place ].reverse_each do |text|
      string = text.last
      color = text[0..-2]
      next if string.empty?
      xPos -= UnicodeUtils.display_width(string)+1
      pad.color(*color)
      pad.write(xPos, 0, string)
    end

    xPos = ColumnDefinitions::COLUMNS[:UsernameColumn]
    yPos = 2

    @tweetline.tweet_pieces.each do |piece|
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

end

#!/usr/bin/env ruby

require 'clipboard'

class PanelSet < ThingContainer

  def timeline_consume_input(input)
    case input
      # Mouse control
      when Ncurses::KEY_MOUSE
        mouse_event = Ncurses::MEVENT.new
        Ncurses::getmouse(mouse_event)
        if mouse_event.bstate & Ncurses::BUTTON1_PRESSED != 0
          select_tweet(top + mouse_event.y-@tweets_panel.pos.y) if mouse_event.y >= @tweets_panel.pos.y && mouse_event.y < @tweets_panel.size.y+@tweets_panel.pos.y
        elsif mouse_event.bstate & Ncurses::BUTTON4_PRESSED != 0
          scroll_top(top-3)
        elsif mouse_event.bstate & Ncurses::BUTTON2_PRESSED != 0 # or mouse_event.bstate & Ncurses::REPORT_MOUSE_POSITION != 0
          scroll_top(top+3)
        end

      # Keyboard control
      else
        if @header == nil
          action = config.keybinds[input]
        else
          action = config.keybinds[@header][input]
          @header = nil
        end

        if action.is_a? Symbol
          method("action_#{action.to_s}").call
        elsif action.is_a? Hash
          @header = input
        end
    end
  end

  def post_consume_input(input)
    case input

      when Ncurses::KEY_MOUSE
        nil

      # Esc
      when 27
        # Exit post mode
        @post = ''
        switch_mode(:timeline)

      # Backspace
      when 127
        # Delete a character
        @post = @post[0..-2]

      # Return
      when "\r".ord
        # Post the tweet
        post_tweet
        @post = ''
        switch_mode(:timeline)

      when Ncurses::KEY_MOUSE
        mouse_event = Ncurses::MEVENT.new
        Ncurses::getmouse(mouse_event)
        @post += mouse_event.bstate.to_s + ' '

      else
        # Every other input is just a character in the post
        @post += input.chr(Encoding::UTF_8)
      #@post += input.to_s
    end
  end

  def confirm_consume_input(input)
    if @confirm_keys.include?(input)
      case @confirm_action
        when :retweet
          @clients.rest_concurrently(:retweet, selected_tweet.tweet.id) { |rest, id| rest.retweet(id) }
          switch_mode(:timeline)
        when :delete
          @clients.rest_concurrently(:delete, selected_tweet.tweet.id) { |rest, id| rest.destroy_status(id) }
          switch_mode(:timeline)
      end
    elsif @deny_keys.include?(input)
      switch_mode(:timeline)
    end
  end

  private

  def action_select_current_selection
    @tweets_panel.select_tweet(selected_index)
    @tweets_panel.update_relations
  end

  def action_select_cursor_up
    select_tweet(selected_index-1)
  end

  def action_select_cursor_down
    select_tweet(selected_index+1)
  end

  def action_select_top_line
    select_tweet(top)
  end

  def action_select_middle_line
    select_tweet(top+(visible_tweets.size-1)/2)
  end

  def action_select_bottom_line
    select_tweet(top+visible_tweets.size-1)
  end

  def action_select_first_line
    select_tweet(0)
  end

  def action_select_last_line
    select_tweet(tweetview.size-1)
  end

  def select_related_line(offset)
    if selected_tweet.is_tweet?
      if @tweetstore.reply_tree.size > 1
        # Reply tree traversal
        rt_index = @tweetstore.reply_tree.find_index { |tl| tl.tweet.id >= selected_tweet.tweet.id }
        rt_index = [ 0, [ rt_index+offset, @tweetstore.reply_tree.size-1 ].min ].max
        ts_index = @tweetstore.find_index { |tl| tl.tweet.id == @tweetstore.reply_tree[rt_index].tweet.id }
        select_tweet(ts_index, false) if ts_index
      else
        # Same user traversal
        ts_index = @tweetstore.find_index { |tl| tl.tweet.id == selected_tweet.tweet.id }
        search_in =
            if offset < 0
              @tweetstore[0...ts_index].reverse
            else
              @tweetstore[ts_index+1..-1]
            end
        si_index = search_in.find_index { |tl| tl.tweet.user.id == selected_tweet.tweet.user.id }
        if si_index
          ts_index = @tweetstore.find_index { |tl| tl.tweet.id == search_in[si_index].tweet.id }
          select_tweet(ts_index, false)
        end
      end
    end
  end

  def action_select_previous_related_line
    select_related_line(-1)
  end

  def action_select_next_related_line
    select_related_line(1)
  end

  def action_scroll_cursor_to_top
    scroll_top(selected_index)
  end

  def action_scroll_cursor_to_middle
    scroll_top(selected_index-(@tweets_panel.size.y-1)/2)
  end

  def action_scroll_cursor_to_bottom
    scroll_top(selected_index-@tweets_panel.size.y+1)
  end

  def action_compose_tweet
    switch_mode(:post)
    @reply_to = nil
  end

  def action_compose_selection_reply(to_all = false)
    return unless selected_tweet.is_tweet? # Do nothing when following stream
    switch_mode(:post)

    # When replying to a retweet, we reply to the retweeted status, not the status that is a retweet
    reply_tweetline = selected_tweet
    @reply_to =
        if reply_tweetline.retweet?
          reply_tweetline.tweet.retweeted_status
        else
          reply_tweetline.tweet
        end

    # Populate the tweet with the @names of people being replied to
    if to_all # Also include @names of every person mentioned in the tweet
      mentioned_users = Twitter::Extractor::extract_mentioned_screen_names(@reply_to.text)
      mentioned_users = mentioned_users.uniq
      mentioned_users.delete(@reply_to.user.screen_name)
      mentioned_users.unshift(@reply_to.user.screen_name)
      mentioned_users.delete(@clients.user.screen_name)
      mentioned_users << reply_tweetline.tweet.user.screen_name if reply_tweetline.retweet?
      mentioned_users.map! { |u| "@#{u}" }
      @post = "#{mentioned_users.join(' ')} "
    else # Only have @name of the user of the tweet
      @post = "@#{@reply_to.user.screen_name} "
    end
  end

  def action_compose_selection_reply_to_all
    action_compose_selection_reply(true)
  end

  def action_selection_favorite
    # TODO: Favorite retweets correctly
    return unless selected_tweet.is_tweet?
    @clients.rest_concurrently(:favorite, selected_tweet.tweet.id) { |rest, id| rest.favorite(id) }
  end

  def action_selection_unfavorite
    # TODO: Don't crash when the tweet is un-unfavoritable
    return unless selected_tweet.is_tweet?
    @clients.rest_concurrently(:unfavorite, selected_tweet.tweet.id) { |rest, id| rest.unfavorite(id) }
  end

  def action_selection_retweet
    return unless selected_tweet.is_tweet? # Do nothing when following stream
    switch_mode(:confirm)
    @confirm_action = :retweet
    @confirm_keys = [ 'y'.ord, 'Y'.ord, 'e'.ord, '\r'.ord ]
    @deny_keys = [ 'n'.ord, 'N'.ord, 27 ] # Esc
    @confirm_text = 'Really retweet this tweet? eyY/nN'
  end

  def action_selection_delete
    return unless selected_tweet.is_tweet? # Do nothing when following stream
    return unless selected_tweet.tweet.user.id == @clients.user.id # Must be own tweet
    switch_mode(:confirm)
    @confirm_action = :delete
    @confirm_keys = [ 'y'.ord, 'Y'.ord, 'd'.ord, '\r'.ord ]
    @deny_keys = [ 'n'.ord, 'N'.ord, 27 ] # Esc
    @confirm_text = 'Really delete this tweet? dyY/nN'
  end

  def action_selection_copy_text
    return unless selected_tweet.is_tweet?
    Clipboard.copy(selected_tweet.extended_text)
    @notice_panel.set_notice('COPIED', 5,5,5)
  end

  def action_selection_copy_link
    return unless selected_tweet.is_tweet?
    if selected_tweet.retweet?
      Clipboard.copy(selected_tweet.tweet.retweeted_tweet.url)
    else
      Clipboard.copy(selected_tweet.tweet.url)
    end
    @notice_panel.set_notice('COPIED LINK', 5,5,5)
  end

  def action_quit
    world.quit
  end

end

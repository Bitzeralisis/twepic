require 'clipboard'
require 'launchy'

module PanelSetConsumeInput

  include ConsumeInput

  private

  def consume_mouse_input(mouse_event)
    if mouse_event.bstate & Ncurses::BUTTON1_PRESSED != 0
      select_tweet(top + mouse_event.y-@tweets_panel.pos.y) if mouse_event.y >= @tweets_panel.pos.y && mouse_event.y < @tweets_panel.size.y+@tweets_panel.pos.y
    elsif mouse_event.bstate & Ncurses::BUTTON4_PRESSED != 0
      scroll_top(top-3)
    elsif mouse_event.bstate & Ncurses::BUTTON2_PRESSED != 0 # or mouse_event.bstate & Ncurses::REPORT_MOUSE_POSITION != 0
      scroll_top(top+3)
    end
  end

  def action_select_current_selection
    select_tweet(selected_index)
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
        tv_index = tweetview.find_index { |tl| tl.is_tweet? and tl.tweet.id == @tweetstore.reply_tree[rt_index].tweet.id }
        select_tweet(tv_index, false) if tv_index
      else
        # Same user traversal
        tv_index = tweetview.find_index { |tl| tl.is_tweet? and tl.tweet.id == selected_tweet.tweet.id }
        search_in =
            if offset < 0
              tweetview[0...tv_index].reverse
            else
              tweetview[tv_index+1..-1]
            end
        si_index = search_in.find_index { |tl| tl.is_tweet? and tl.tweet.user.id == selected_tweet.tweet.user.id }
        if si_index
          tv_index = tweetview.find_index { |tl| tl.is_tweet? and tl.tweet.id == search_in[si_index].tweet.id }
          select_tweet(tv_index, false)
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
    @post_panel.set_target(post: '', reply_to: nil)
    switch_mode(:post)
  end

  def action_compose_selection_reply(to_all = false)
    return unless selected_tweet.is_tweet? # Do nothing when following stream

    # When replying to a retweet, we reply to the retweeted status, not the status that is a retweet
    reply_tweetline = selected_tweet
    reply_to = reply_tweetline.root_twepic_tweet

    # Populate the tweet with the @names of people being replied to
    if to_all # Also include @names of every person mentioned in the tweet
      mentioned_users = Twitter::Extractor::extract_mentioned_screen_names(reply_to.extended_text)
      mentioned_users = mentioned_users.uniq
      mentioned_users.delete(reply_to.tweet.user.screen_name)
      mentioned_users.unshift(reply_to.tweet.user.screen_name)
      mentioned_users.delete(@clients.user.screen_name)
      mentioned_users << reply_tweetline.tweet.user.screen_name if reply_tweetline.retweet?
      mentioned_users.map! { |u| "@#{u}" }
      post = mentioned_users.empty? ? '' : "#{mentioned_users.join(' ')} "
    else # Only have @name of the user of the tweet
      post = "@#{reply_to.tweet.user.screen_name} "
    end

    @post_panel.set_target(post: post, reply_to: reply_to.tweet)
    switch_mode(:post)
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
    @confirm_panel.set_action(
        action_type: :retweet,
        action_text: 'Really retweet this tweet? eyY/nN',
        confirm_keys: [ 'y'.ord, 'Y'.ord, 'e'.ord, '\r'.ord ],
        deny_keys: [ 'n'.ord, 'N'.ord, 27 ] # Esc
    )
  end

  def action_selection_delete
    return unless selected_tweet.is_tweet? # Do nothing when following stream
    return unless selected_tweet.tweet.user.id == @clients.user.id # Must be own tweet
    switch_mode(:confirm)
    @confirm_panel.set_action(
        action_type: :delete,
        action_text: 'Really delete this tweet? dyY/nN',
        confirm_keys: [ 'y'.ord, 'Y'.ord, 'd'.ord, '\r'.ord ],
        deny_keys: [ 'n'.ord, 'N'.ord, 27 ] # Esc
    )
  end

  def action_selection_copy_text
    return unless selected_tweet.is_tweet?
    Clipboard.copy(selected_tweet.extended_text)
    set_notice('COPIED TWEET', 5,5,5)
  end

  def action_selection_copy_link
    return unless selected_tweet.is_tweet?
    Clipboard.copy(selected_tweet.root_tweet.url)
    set_notice('COPIED TWEET LINK', 5,5,5)
  end

  def action_selection_open_link_external
    return unless selected_tweet.is_tweet?
    Launchy.open(selected_tweet.root_tweet.url)
    set_notice('OPENING TWEET IN BROWSER...', 5,5,5)
  end

  def action_tab_select_left
    switch_tab(@current_tab == 0 ? @tabs.size-1 : @current_tab-1)
  end

  def action_tab_select_right
    switch_tab(@current_tab == @tabs.size-1 ? 0 : @current_tab+1)
  end

  def action_tab_delete
    return if @current_tab == 0
    @tabs.delete_at(@current_tab)
    switch_tab(@current_tab == @tabs.size ? @current_tab-1 : @current_tab)
  end

  def action_selection_new_tab_user_tweets
    return unless selected_tweet.is_tweet?

    selected = selected_tweet
    id = selected.tweet.user.id
    view = StreamingTweetView.new(@tweets_panel, "USER: @#{selected.tweet.user.screen_name}") do |tl|
      tl.tweet.user.id == id
    end
    @tweetstore.each { |tt| view << TweetLine.new(@tweets_panel, tt, @time-1000) if tt.tweet.user.id == selected.tweet.user.id }
    index = view.find_index { |tl| tl.tweet.id == selected.tweet.id }
    view.select_tweet(index, true, @tweets_panel.size.y)

    @tweetstore.attach_view(view)
    @tabs << view
    switch_tab(@tabs.size-1)
  end

  def action_selection_new_tab_related_tweets
    return unless selected_tweet.is_tweet?

    return action_selection_new_tab_user_tweets if @tweetstore.reply_tree.size == 1

    selected = selected_tweet
    view = TweetView.new(@tweets_panel, 'REPLY TREE')
    @tweetstore.reply_tree.each { |tt| view << TweetLine.new(@tweets_panel, tt, @time-1000) }
    index = view.find_index { |tl| tl.tweet.id == selected.tweet.id }
    view.select_tweet(index, true, @tweets_panel.size.y)

    @tweetstore.attach_view(view)
    @tabs << view
    switch_tab(@tabs.size-1)
  end

  def action_detail_panel_mode
    switch_mode(:detail)
  end

  def action_quit
    world.quit
  end

end

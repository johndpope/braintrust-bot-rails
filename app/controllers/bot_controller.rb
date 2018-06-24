require "#{Rails.root}/lib/helpers/application_helpers"
require 'open-uri'
require 'fileutils'
include ApplicationHelpers

class BotController < Telegram::Bot::UpdatesController

  PREFIXES = %w(@channel @everyone @all @people)
  PREFIXES << "@#{Telegram.bot.username.downcase}" if Telegram.bot.username.present?

  before_action :find_or_create_chat, :find_or_create_user, :add_members, :remove_member

  use_session!

  def message(update)
    return if @user.nil?

    session.delete :photo

    # assume that the next message they send means they don't want to add location (unless that message is a location)
    latest_quote = @user.quotes.order(created_at: :desc).where(location_confirmed: false, chat: @chat).first

    unless latest_quote.nil?
      latest_quote.location_confirmed = true
      latest_quote.save
    end

    if update.key?('photo')
      photo_sizes = update['photo']

      # pick the largest photo of all sent
      largest_photo = photo_sizes.reduce do |acc, photo|
        acc['file_size'] > photo['file_size'] ? acc : photo
      end

      # cache the photo ID in case they want to save it
      session[:photo] = largest_photo['file_id']
    end

    # handle messages that begin with special prefixes
    if update.key?('text')
      PREFIXES.each do |prefix|
        if update['text'].downcase.starts_with?(prefix)
          # pluck out the text from the update, cut out the @botusername part,
          # split it into an array (as summon would expect), and splat it for args to summon
          summon! *update['text'][prefix.length..-1].split(' ')
          return
        end
      end
    end

    # if there's a location in the update and the sender's latest quote does not have a confirmed location
    # then add the longitude and latitude to their location (for Gwen)
    if update.key?('location') && !latest_quote.nil?
      # get the latest quote sent by this sender in this chat
      location = update['location']

      latest_quote.longitude = location['longitude']
      latest_quote.latitude = location['latitude']
      latest_quote.save
      respond_with :message, text: '🗺 A location was added to your latest quote!'
    end
  end

  # send a photo to the chat
  # uses the :photo key in the session store -- if it's not there, then they didn't send a photo
  # *args is an optional caption
  def sendphoto!(*args)
    return if @user.nil?

    if session.key? :photo
      new_photo = @chat.photos.new member: @user, telegram_photo: session[:photo], caption: args.join(' ')

      if new_photo.save
        cached_response = respond_with :message, text: "🌄 Your photo is being saved..."

        # since this involves downloading a real photo from Telegram, it's not really something we can test...
        unless Rails.env == 'test'
          # prepare to download the file now that we definitely want to keep it
          file_info = bot.get_file(file_id: session[:photo])
          url = "https://api.telegram.org/file/bot#{ENV['BOT_TOKEN']}/#{file_info['result']['file_path']}"
          ext = file_info['result']['file_path'].partition('.').last

          ext = "jpg" unless ext.present?

          # make a directory with this chat ID if it doesn't already exist
          dirname = Rails.root.join('telegram_images', @chat.id.to_s).to_s
          unless File.directory?(dirname)
            FileUtils.mkdir_p(dirname)
          end

          # save photo locally to /images/<chat_id>/<photo_id>.<ext> (id = the id in our database, not telegram's)
          dl_image = open(url)
          IO.copy_stream(dl_image, dirname + "/#{new_photo.id}.#{ext}")

          bot.public_send('edit_message_text', text: "🌄 Your photo was saved!",
                          chat_id: cached_response['result']['chat']['id'],
                          message_id: cached_response['result']['message_id'])
        end

        session.delete :photo
      else
        respond_with :message, text: "🤬 Failed to save photo: #{new_photo.errors.full_messages} (@SamWolfson should fix this)"
      end

    else
      respond_with :message, text: "🧐 You didn't send a photo!"
    end
  end

  # shorthand for sendphoto
  def sp!(*args)
    sendphoto!(*args)
  end

  # get back a random photo that was sent to the chat
  def getphoto!(*)
    photos = @chat.photos

    if photos.empty?
      respond_with :message, text: "😭 You don't have any photos! Use /sendphoto to add some.", parse_mode: :html
    else
      photo = photos.sample.increment! :times_accessed
      respond_with :photo, photo: photo.telegram_photo, caption: photo.caption
    end
  end

  # shorthand for getphoto
  def gp!(*)
    getphoto!(*[])
  end

  # The format of a quote is
  # content && author && context
  # where context is optional.
  def sendquote!(*args)
    return if @user.nil?

    # tokenize the quote into content, author, and (optional) context
    tokens = args.join(' ').split('&&')

    # we need either 2 or 3 tokens for a valid quote
    unless tokens.length.between?(2, 3)
      respond_with :message, text: "🧐 Usage: /sendquote [quote] && [author] && [optional context]"
      return
    end

    tokens.map! { |t| t.strip } # remove leading and trailing whitespace
    new_quote = @chat.quotes.new content: tokens[0], author: tokens[1], member: @user

    if tokens.length == 3
      new_quote.context = tokens[2]
    end

    if new_quote.save
      respond_with :message, text: '👌 Your quote was saved!'
    else
      respond_with :message, text: "🤬 Failed to save quote: #{new_quote.errors.full_messages} (@SamWolfson should fix this)"
    end
  end

  # shortcut method for sendquote
  def sq!(*args)
    sendquote!(*args)
  end

  def getquote!(*args)
    # the sender can optionally pass the author as an argument if they only want specific authors
    author = args.join(' ').presence # returns the text if non-empty; otherwise nil

    # 10% chance of getting a Markov quote
    quote = @chat.random_quote (rand(10) > 8), author

    if quote.nil?
      respond_with :message, text: "😭 You don't have any quotes#{" by <b>#{author}</b>" if author}! Use /sendquote to add some.", parse_mode: :html
    else
      respond_with :message, text: format_quote(quote.content, quote.author, quote.context, quote.created_at.year), parse_mode: :html
    end
  end

  # shortcut method for getquote
  def gq!(*args)
    getquote!(*args)
  end

  # shortcut method for getquote and sendquote
  # if no arguments are passed, calls getquote; else calls sendquote
  def quote!(*args)
    if args.empty?
      getquote! *args
    else
      sendquote! *args
    end
  end

  # get all members in the chat group
  def members!
    chat_members = @chat.members.map { |m| "#{pretty_name(m, true)}" }
    respond_with :message, text: "📜 Chat group members: #{chat_members.sort.to_sentence}", parse_mode: :html
  end

  # send a summon to all messages in the chat group, with an optional message
  def summon!(*message)
    if @user
      @user.chat_members.find_by_chat_id(@chat.id).increment! :summons_performed
    end

    chat_members = @chat.members
                       .select { |m| m.username.present? && m.username != from['username'].downcase }
                       .map { |m| "@#{m.username}" }

    announcement = "📣 <b>#{ if from.key? 'first_name' then from['first_name'] else from['username'] end }</b>\n"

    if message.empty?
      announcement << "\n"
    else
      announcement << message.join(' ').strip << "\n\n"
    end

    announcement << chat_members.sort.join(', ')

    respond_with :message, text: announcement, parse_mode: :html
  end

  # shorthand for summon
  def s!(*message)
    summon! *message
  end

  def quotes!(*preferences)
    if preferences.length != 1
      respond_with :message, text: "🧐 Usage: /quotes [enable | disable]"
      return
    end

    preference = preferences[0]

    if preference == 'enable'
      @chat.quotes_enabled = true
      respond_with :message, text: "🙌 Quotes enabled!"
    elsif preference == 'disable'
      @chat.quotes_enabled = false
      respond_with :message, text: "🤐 Quotes disabled!"
    else
      respond_with :message, text: "🧐 Usage: /quotes [enable | disable]"
      return
    end

    @chat.save
  end

  def on_8ball!(*)
    answer = @chat.eight_ball_answers.sample

    if answer.nil?
      respond_with :message, text: "🤐 <i>You've got no answers, guess you're SOL.</i>", parse_mode: :html
    else
      respond_with :message, text: "<i>#{answer.answer}</i>", parse_mode: :html
    end
  end

  alias_method '8ball!', :on_8ball!

  def luck!
    response = "🍀 <b>Luck Statistics</b>\n"

    statistics = @chat.members.map do |m|
      [m.luck, pretty_name(m)]
    end

    statistics.sort! do |a, b|
      b.first <=> a.first
    end

    a = statistics.map do |s|
      "<b>#{s.first}:</b> #{s.second}"
    end

    response << a.join("\n")

    respond_with :message, text: response, parse_mode: :html
  end


  private

  def find_or_create_chat
    @chat = Chat.where(telegram_chat: chat['id']).first_or_create

    # update title if necessary
    @chat.title = chat['title']
    @chat.save
  end

  # if the message contains newuply added chat members, then add them to the chat automatically
  def add_members
    if update.dig('message', 'new_chat_members')
      added = []
      no_username = false

      update['message']['new_chat_members'].each do |m|
        next if m['is_bot']

        no_username = !m['username'].present?

        new_member = Member.find_by_telegram_user m['id']
        new_member ||= Member.find_by_username m['username'].downcase if m['username'].present?
        new_member ||= Member.new telegram_user: m['id']

        new_member.first_name = m['first_name'] if m['first_name'].present?
        new_member.last_name = m['last_name'] if m['last_name'].present?
        new_member.username = m['username'].downcase if m['username'].present?

        unless new_member.chats.include?(@chat.id)
          new_member.chats << @chat
        end

        new_member.save!
        added << new_member
      end

      unless added.empty?
        pretty_users = added.map do |a|
          result = pretty_name(a, true)
          # notify users that they should add a username
          result << "<b>*</b>" unless a.username.present?
          result
        end

        message = "#{added.size == 1 ? 'was' : 'were'} added to the chat group."

        message << "\n\n<b>*</b> should add a username before they can be included in summons." if no_username

        respond_with :message, text: "❤️ #{pretty_users.to_sentence} #{message}", parse_mode: :html
      end
    end
  end

  # if the message contains removed members, then remove them
  def remove_member
    if update.dig('message', 'left_chat_member')
      left = update['message']['left_chat_member']

      return if left['is_bot']

      member = @chat.members.find_by_telegram_user left['id']
      member ||= @chat.members.find_by_username left['username'].downcase

      unless member.nil?
        @chat.members.delete member
        respond_with :message, text: "💔 #{pretty_name(member, true)} was removed from the chat group.", parse_mode: :html
      end
    end
  end

  # check the sender of each message to see whether they're part of this chat group.
  # if not, create the user as necessary and add them
  def find_or_create_user
    if from['is_bot']
      @user = nil
      return
    end

    # try and find by ID
    @user = Member.find_by_telegram_user from['id']

    if @user.nil?
      # try and find by username
      @user = Member.find_by_username from['username'].downcase if from['username'].present?

      if @user.nil?
        @user = Member.new telegram_user: from['id']
      else
        # update their ID to match
        @user.telegram_user = from['id']
      end
    end

    # update their username and first/last names because we know their ID (always stay up to date!)
    @user.username = from['username'].downcase if from['username'].present?
    @user.first_name = from['first_name'] if from['first_name'].present?
    @user.last_name = from['last_name'] if from['last_name'].present?

    # add new members automatically
    unless @user.chats.exists?(@chat.id)
      @user.chats << @chat
      response = "❤️ #{pretty_name(@user, true)} was added to the chat group."
      response << " (They should add a username before they can be included in summons.)" unless @user.username.present?

      respond_with(:message, text: response, parse_mode: :html)
    end

    unless @user.save
      respond_with :message, text: "⚠️ Failed to update #{from['username']}. (#{@user.errors.full_messages})"
    end
  end
end
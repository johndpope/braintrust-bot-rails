require 'rails_helper'

RSpec.describe BotController, telegram_bot: :rails do

  def create_message(uid)
    {
        from: {
            id: "99#{uid}",
            username: "uSer#{uid}"
        },
        chat: {
            id: 2468,
            title: 'TestChat'
        }
    }
  end

  describe 'basic functionality' do
    it 'creates a chat group and user when a message is sent' do
      message = {
          from: {
              id: 1234,
              username: 'test_user'
          },
          chat: {
              id: 2468,
              title: 'TestChat'
          }
      }
      expect { dispatch_message 'Hello', message }.to send_telegram_message(bot, /<b>test_user<\/b> was added to the chat group/)

      # verify that member and chat were created
      expect(Member.where(username: 'test_user', telegram_user: '1234')).to exist
      expect(Chat.where(title: 'TestChat', telegram_chat: '2468')).to exist

      m = Chat.first.members.first

      expect(m).not_to be_nil
      expect(m.telegram_user).to eq(1234)
    end

    it 'does not add members multiple times' do
      message = {
          from: {
              id: 1234,
              username: 'test_user'
          },
          chat: {
              id: 2468,
              title: 'TestChat'
          }
      }

      10.times do |_|
        dispatch_message 'Hello', message
      end

      expect(Member.all.size).to eq(1)
      expect(Chat.all.size).to eq(1)
    end

    it 'correctly adds users without usernames' do
      message = {
          from: {
              id: 1234,
              first_name: 'foo',
              last_name: 'bar'
          },
          chat: {
              id: 2468,
              title: 'TestChat'
          }
      }

      dispatch_message 'Hello', message

      expect(Member.all.size).to eq(1)
      expect(Chat.all.size).to eq(1)

      m = Member.first
      expect(m.username).not_to be_truthy
      expect(m.first_name).to eq('foo')
      expect(m.last_name).to eq('bar')
      expect(m.chats.first.title).to eq('TestChat')
    end

    it 'updates when a chat is renamed' do
      message = {
          from: {
              id: 1234,
              username: 'test_user'
          },
          chat: {
              id: 2468,
              title: 'TestChat'
          }
      }

      dispatch_message 'hello, world!', message

      chat = Chat.first

      expect(chat.telegram_chat).to eq 2468
      expect(chat.title).to eq "TestChat"

      message[:chat][:title] = "RenamedChat"

      dispatch_message 'hello, world!', message

      chat.reload

      expect(chat.telegram_chat).to eq 2468
      expect(chat.title).to eq "RenamedChat"
    end

    it 'adds new users when a different user adds them to the chat' do
      new_chat_members = create_message(1)
      new_chat_members[:new_chat_members] = Array.new

      (2..6).each do |i|
        new_chat_members[:new_chat_members] << {
            id: "1234#{i}",
            username: "test_usEr#{i}"
        }
      end

      expected_users = (2..6).map do |i|
        "<b>test_user#{i}</b>"
      end

      expect { dispatch_message '', new_chat_members }.to send_telegram_message(bot, Regexp.new(expected_users.to_sentence))

      expect(Chat.all.size).to eq 1
      expect(Chat.first.members.all.size).to eq 6
    end

    it 'does not add users who are bots' do
      fake_bot = create_message(1)
      fake_bot[:from][:is_bot] = true
      fake_bot[:from][:username] = "NotARealBot"

      adder = create_message(2)
      adder[:new_chat_members] = Array.new
      adder[:new_chat_members] << fake_bot[:from]

      dispatch_message '', create_message(2)

      expect(Chat.all.size).to eq 1
      expect(Member.all.size).to eq 1

      dispatch_message 'I love bots!', adder

      expect(Chat.all.size).to eq 1
      expect(Member.all.size).to eq 1

      dispatch_message 'I am a bot!', fake_bot

      expect(Chat.all.size).to eq 1
      expect(Member.all.size).to eq 1
    end

    it 'lists chat members' do
      m1 = create_message(1)
      m1[:from][:first_name] = "f1"
      m1[:from][:last_name] = "l1"

      m2 = create_message(2)
      m2[:from][:first_name] = "f2"

      m3 = create_message(3)

      expect { dispatch_message '', m1 }.to send_telegram_message(bot, /<b>f1 l1<\/b> was added/)
      expect { dispatch_message '', m2 }.to send_telegram_message(bot, /<b>f2<\/b> was added/)
      expect { dispatch_message '', m3 }.to send_telegram_message(bot, /<b>user3<\/b> was added/)

      expect { dispatch_command 'members', m1 }.to send_telegram_message(bot, /f1(.*)l1(.*)f2(.*)and(.*)user3/)
    end

    it 'updates users without IDs' do
      dispatch_message '', create_message(2)

      m = Chat.first.members.create! username: "user1"
      expect(m.telegram_user).to be_falsey

      dispatch_message '', create_message(1)

      m.reload

      expect(m.telegram_user).to eq(991)
    end

    it 'updates users without usernames' do
      dispatch_message '', create_message(2)

      m = Chat.first.members.create! telegram_user: 991
      expect(m.username).to be_falsey

      dispatch_message '', create_message(1)

      m.reload

      expect(m.username).to eq('user1')
    end

    it 'adds users without usernames' do
      message = {
          from: {
              id: 1234,
              first_name: 'foo',
              last_name: 'bar'
          },
          chat: {
              id: 2468,
              title: 'TestChat'
          }
      }

      expect { dispatch_message '', message }.to send_telegram_message(bot, /foo bar(.*)add a username/)
    end

    it 'adds new users without usernames when a different user adds them to the chat' do
      new_chat_members = create_message(1)
      new_chat_members[:new_chat_members] = Array.new

      (2..6).each do |i|
        new_chat_members[:new_chat_members] << {
            id: 12340 + i,
            first_name: "first#{i}"
        }
      end

      expected_users = (2..6).map do |i|
        "<b>first#{i}</b><b>\\*</b>"
      end

      expect { dispatch_message '', new_chat_members }.to(
          send_telegram_message(bot, Regexp.new("#{expected_users.to_sentence}(.*)should", Regexp::MULTILINE))
      )

      expect(Chat.all.size).to eq 1
      expect(Chat.first.members.all.size).to eq 6
    end

    it 'removes users' do
      dispatch_message '', create_message(1)
      dispatch_message '', create_message(2)

      expect(Chat.all.size).to eq 1
      expect(Member.all.size).to eq 2
      expect(Chat.first.members.size).to eq 2

      removal_message = create_message(1)
      removal_message[:left_chat_member] = create_message(2)[:from]

      expect { dispatch_message '', removal_message }.to send_telegram_message(bot, /<b>user2<\/b> was removed/)

      expect(Chat.all.size).to eq 1
      expect(Member.all.size).to eq 2
      expect(Chat.first.members.size).to eq 1
      expect(Chat.first.members.first.telegram_user).to eq 991
    end

    it 'removes users without usernames' do
      dispatch_message '', create_message(1)

      removed_user = create_message(2)
      removed_user[:from].delete :username
      removed_user[:from][:first_name] = 'sadboi'

      dispatch_message '', removed_user

      expect(Chat.all.size).to eq 1
      expect(Member.all.size).to eq 2
      expect(Chat.first.members.size).to eq 2

      removal_message = create_message(1)
      removal_message[:left_chat_member] = removed_user[:from]

      expect { dispatch_message '', removal_message }.to send_telegram_message(bot, /<b>sadboi<\/b> was removed/)

      expect(Chat.all.size).to eq 1
      expect(Member.all.size).to eq 2
      expect(Chat.first.members.size).to eq 1
      expect(Chat.first.members.first.telegram_user).to eq 991
    end

    it 'does not duplicate a user with a telegram ID in multiple chats' do
      dispatch_message '', create_message(1)

      expect(Chat.all.size).to eq 1
      expect(Member.all.size).to eq 1
      expect(Chat.first.members.size).to eq 1

      new_chat = create_message(1)
      new_chat[:chat][:id] = 2469

      dispatch_message '', new_chat

      expect(Chat.all.size).to eq 2
      expect(Member.all.size).to eq 1
      expect(Chat.first.members.size).to eq 1
      expect(Chat.second.members.size).to eq 1

      expect(Chat.second.members.first).to eq(Chat.first.members.first)
    end

    it 'does not duplicate a user without a telegram ID in multiple chats' do
      m = create_message(1)
      m[:from].delete(:telegram_user)

      dispatch_message '', m

      expect(Chat.all.size).to eq 1
      expect(Member.all.size).to eq 1
      expect(Chat.first.members.size).to eq 1

      new_chat = m
      new_chat[:chat][:id] = 2469

      dispatch_message '', new_chat

      expect(Chat.all.size).to eq 2
      expect(Member.all.size).to eq 1
      expect(Chat.first.members.size).to eq 1
      expect(Chat.second.members.size).to eq 1

      expect(Chat.second.members.first).to eq(Chat.first.members.first)
    end
  end

  describe 'summoning' do

    it 'summons all users in a chat group' do
      (1..5).to_a.reverse.each do |i|
        dispatch_message 'Hello', create_message(i)
      end

      expect(Member.all.size).to eq(5)
      expect(Chat.all.size).to eq(1)

      expected_response = /#{(2..5).map {|i| "@user#{i}"}.join ', '}/

      # make sure it works with `/summon` and `/s`
      %w(summon s).each do |command|
        expect { dispatch_command command, create_message(1)}.to send_telegram_message(bot, expected_response)
      end
    end

    it 'summons when using other prefixes' do
      (1..5).to_a.reverse.each do |i|
        dispatch_message 'Hello', create_message(i)
      end

      expected_response = /#{(2..5).map {|i| "@user#{i}"}.join ', '}/

      BotController::PREFIXES.each do |prefix|
        expect { dispatch_message prefix, create_message(1)}.to send_telegram_message(bot, expected_response)
      end
    end

    it 'summons using a message' do
      expect { dispatch_command 's I am a command', create_message(1) }.to send_telegram_message(bot, /I am a command/)
    end

    it 'ignores users without usernames and sender when summoning' do
      message = {
          from: {
              id: 1234,
              first_name: 'foo',
              last_name: 'bar'
          },
          chat: {
              id: 2468,
              title: 'TestChat'
          }
      }

      dispatch_message 'Hello', message

      5.times do |i|
        dispatch_message "hello world", create_message(i)
      end

      expect { dispatch_command 's', create_message(1) }.to send_telegram_message(bot, /^[(foo)|(@user1)]/)
    end
  end

  describe 'saving quotes' do
    it 'saves quotes from new users' do
      expect { dispatch_command 'sendquote This is a test quote && Test user', create_message(1) }.to(
          send_telegram_message(bot, /Your quote was saved/)
      )

      expect(Chat.all.size).to eq(1)
      expect(Member.all.size).to eq(1)
      expect(Quote.all.size).to eq(1)

      q = Chat.first.quotes.first

      expect(q).not_to be_nil
      expect(q.content).to match(/This is a test quote/)
      expect(q.author).to match(/Test user/)
      expect(q.member).to eq(Member.first)
      expect(Member.first.quotes.first).to eq(q)
    end

    it 'saves quotes with context' do
      expect { dispatch_command 'sendquote This is a test quote && Test user && some context', create_message(1) }.to(
          send_telegram_message(bot, /Your quote was saved/)
      )

      expect(Chat.first.quotes.first.context).to match(/some context/)
    end

    it 'saves location information' do
      expect { dispatch_command 'sendquote This is a test quote && Test user', create_message(1) }.to(
          send_telegram_message(bot, /Your quote was saved/)
      )

      message = create_message(1)
      message['location'] = {
          'longitude': 100,
          'latitude': 200
      }

      expect { dispatch_message '', message }.to send_telegram_message(bot, /A location was added to your latest quote/)

      q = Chat.first.quotes.first

      expect(q.location_confirmed).to be_truthy
      expect(q.longitude).to eq(100)
      expect(q.latitude).to eq(200)

      # sanity check normal quote things
      expect(q.member).to eq(Chat.first.members.first)
      expect(q.content).to match(/This is a test quote/)
      expect(q.author).to match(/Test user/)
    end

    it 'sets confirmed for quotes with no location' do
      expect { dispatch_command 'sendquote This is a test quote && Test user', create_message(1) }.to(
          send_telegram_message(bot, /Your quote was saved/)
      )

      expect(Chat.first.quotes.first.location_confirmed).to be_falsey

      dispatch_message 'not a location', create_message(1)

      expect(Chat.first.quotes.first.location_confirmed).to be_truthy
    end

    it 'works with shorthand command /sq' do
      expect { dispatch_command 'sq This is a test quote && Test user', create_message(1) }.to(
          send_telegram_message(bot, /Your quote was saved/)
      )

      q = Chat.first.quotes.first

      expect(q.member).to eq(Chat.first.members.first)
      expect(q.content).to match(/This is a test quote/)
      expect(q.author).to match(/Test user/)
    end

    it 'gives feedback for malformed commands' do
      expect { dispatch_command 'sq', create_message(1) }.to(
          send_telegram_message(bot, /Usage/)
      )

      expect { dispatch_command 'sq foo && bar && baz && quux', create_message(1) }.to(
          send_telegram_message(bot, /Usage/)
      )
    end

    it 'works with /quote command' do
      expect { dispatch_command 'quote This is a test quote && Test user', create_message(1) }.to(
          send_telegram_message(bot, /Your quote was saved/)
      )

      q = Chat.first.quotes.first

      expect(q.member).to eq(Chat.first.members.first)
      expect(q.content).to match(/This is a test quote/)
      expect(q.author).to match(/Test user/)
    end
  end

  describe 'retrieving quotes' do
    it 'retrieves a random quote' do
      2.times do |i|
        dispatch_command "sq test#{i} && user#{i}", create_message(2)
      end

      expect(Chat.first.quotes.size).to eq(2)

      10.times do |_|
        expect { dispatch_command 'getquote', create_message(1) }.to send_telegram_message(bot, /(test0)|(test1)/)
      end

      10.times do |_|
        expect { dispatch_command 'gq', create_message(1) }.to send_telegram_message(bot, /(test0)|(test1)/)
      end
    end

    it 'handles no quotes gracefully' do
      expect { dispatch_command 'getquote', create_message(1) }.to send_telegram_message(bot, /don't have any quotes/)
    end

    it 'works with /quote command when given no arguments' do
      expect { dispatch_command 'quote', create_message(1) }.to send_telegram_message(bot, /don't have any quotes/)
    end
  end

  describe 'sending photos' do
    it 'saves photos when no messages are sent in between' do
      message = create_message(1).stringify_keys

      msg_with_photo = message.clone

      msg_with_photo['photo'] = [
          {
              'file_size': 128,
              'file_id': 'smallerphoto'
          },
          {
              'file_size': 512,
              'file_id': 'largestphoto'
          },
          {
              'file_size': 256,
              'file_id': 'largerphoto'
          },
      ]

      dispatch_message('this is a photo', msg_with_photo)

      expect { dispatch_message '/sendphoto', message }.to send_telegram_message(bot, /Your photo is being saved/)

      p = Chat.first.photos.first

      expect(p.telegram_photo).to eq('largestphoto')
      expect(Member.first.photos.first).to eq(p)
    end

    it 'discards photos when the same user sends a message in between' do
      message = create_message(1).stringify_keys

      msg_with_photo = message.clone

      msg_with_photo['photo'] = [
          {
              'file_size': 128,
              'file_id': 'smallerphoto'
          },
          {
              'file_size': 512,
              'file_id': 'largestphoto'
          },
          {
              'file_size': 256,
              'file_id': 'largerphoto'
          },
      ]

      dispatch_message('this is a photo', msg_with_photo)

      dispatch_message('this is a message in between', message)

      expect { dispatch_message '/sendphoto', message }.to send_telegram_message(bot, /You didn't send a photo/)

      expect(Chat.first.photos.size).to eq(0)
    end

    it 'preserves photos when a different user sends a message in between' do
      message = create_message(1).stringify_keys

      msg_with_photo = message.clone

      msg_with_photo['photo'] = [
          {
              'file_size': 128,
              'file_id': 'smallerphoto'
          },
          {
              'file_size': 512,
              'file_id': 'largestphoto'
          },
          {
              'file_size': 256,
              'file_id': 'largerphoto'
          },
      ]

      dispatch_message('this is a photo', msg_with_photo)

      dispatch_message('message in the way!!!', create_message(2))

      expect { dispatch_message '/sp', message }.to send_telegram_message(bot, /Your photo is being saved/)

      p = Chat.first.photos.first

      expect(p.telegram_photo).to eq('largestphoto')
      expect(Member.first.photos.first).to eq(p)
    end
  end

  describe 'retrieving photos' do
    it 'retrieves a photo with no caption' do
      message = create_message(1).stringify_keys

      msg_with_photo = message.clone

      msg_with_photo['photo'] = [
          {
              'file_size': 128,
              'file_id': 'smallerphoto'
          },
          {
              'file_size': 512,
              'file_id': 'largestphoto'
          },
          {
              'file_size': 256,
              'file_id': 'largerphoto'
          },
      ]

      dispatch_message('this is a photo', msg_with_photo)

      expect { dispatch_message '/sendphoto', message }.to send_telegram_message(bot, /Your photo is being saved/)

      p = Chat.first.photos.first

      expect(p.telegram_photo).to eq('largestphoto')
      expect(Member.first.photos.first).to eq(p)

      expect { dispatch_message '/getphoto', create_message(1) }
          .to (make_telegram_request(bot, :sendPhoto).with(photo: 'largestphoto', caption: '', chat_id: 2468))
    end

    it 'retrieves a photo with a caption' do
      message = create_message(1).stringify_keys

      msg_with_photo = message.clone

      msg_with_photo['photo'] = [
          {
              'file_size': 128,
              'file_id': 'smallerphoto'
          },
          {
              'file_size': 512,
              'file_id': 'largestphoto'
          },
          {
              'file_size': 256,
              'file_id': 'largerphoto'
          },
      ]

      dispatch_message('this is a photo', msg_with_photo)

      expect { dispatch_message '/sendphoto I am a caption', message }.to send_telegram_message(bot, /Your photo is being saved/)

      p = Chat.first.photos.first

      expect(p.telegram_photo).to eq('largestphoto')
      expect(Member.first.photos.first).to eq(p)

      expect { dispatch_message '/getphoto', create_message(1) }
          .to (make_telegram_request(bot, :sendPhoto).with(photo: 'largestphoto', caption: 'I am a caption', chat_id: 2468))
    end

    it 'handles no photos gracefully' do
      expect { dispatch_message '/getphoto', create_message(1) }
          .to (send_telegram_message(bot, /You don't have any photos/))
    end

    it 'works with alternate command /gp' do
      expect { dispatch_message '/gp', create_message(1) }
          .to (send_telegram_message(bot, /You don't have any photos/))
    end
  end

  describe 'toggling daily quotes' do
    it 'enables daily quotes' do
      expect { dispatch_command 'quotes enable' }.to send_telegram_message(bot, /Quotes enabled/)
      expect(Chat.first.quotes_enabled).to be_truthy
    end

    it 'disables daily quotes' do
      expect { dispatch_command 'quotes disable' }.to send_telegram_message(bot, /Quotes disabled/)
      expect(Chat.first.quotes_enabled).to be_falsey
    end

    it 'handles bogus commands' do
      expect { dispatch_command 'quotes' }.to send_telegram_message(bot, /Usage/)
      expect { dispatch_command 'quotes fasdf adsjh33' }.to send_telegram_message(bot, /Usage/)
      expect { dispatch_command 'quotes fasdf' }.to send_telegram_message(bot, /Usage/)
    end
  end

  describe 'using 8ball' do
    it 'correctly handles empty 8ball' do
      expect { dispatch_command '8ball', create_message(1) }.to send_telegram_message(bot, /You've got no answers/)
    end

    it 'gives sage advice when the 8ball is rolled' do
      c = Chat.create! telegram_chat: '2468'
      c.eight_ball_answers.create! answer: "Some great advice"
      c.eight_ball_answers.create! answer: "Some amazing advice"

      expect { dispatch_command '8ball', create_message(1) }.to send_telegram_message(bot, /(great)|(amazing)/)
    end
  end

  describe 'predicting user luck' do
    it 'responds to /luck' do
      2.times do |i|
        dispatch_message('', create_message(i))
      end

      expect { dispatch_command 'luck', create_message(1) }.to(
          send_telegram_message(bot, Regexp.new("50(.*)user0(.*)50(.*)user1", Regexp::MULTILINE))
      )
    end
  end
end
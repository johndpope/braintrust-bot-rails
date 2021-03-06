# BrainTrust Bot: On Rails

[![Build Status](https://travis-ci.com/terabyte128/braintrust-bot-rails.svg?branch=master)](https://travis-ci.com/terabyte128/braintrust-bot-rails)

Now available via Telegram! Add `@BrainTrustBot` to your chat to get started!

A re-write of the original [BrainTrust Bot](https://github.com/terabyte128/braintrust-bot), but with Ruby on Rails and better planning. 
The original bot has served its purpose well for multiple years, but it's time to start on something built from the ground-up. 

The original bot has been subject to "feature creep" and, given the lack of foresight when it was originally written, did not handle this well. 
A lot of its features were "hacked on" because we originally did not anticipate their existence. So this is an attempt to start over, with a 
better understanding of which features were actually useful and how to implement them in a reasonable way.

### Planned Features

**Summons**

- [X] Send a message to all members of a chat by tagging them all, so they'll be notified even if the chat is muted

**Quotes**

- [X] Store quotes from a chat (message text, author, sender, context)
- [X] Quotes with locations (optional)
- [X] Retrive quotes at random
- [X] Alexa support (ask Alexa for a random quote)
- [X] Automatically send quotes once a day with some probability (can be disabled)
- [X] Automatic quote generation based on Markov chains and all quotes collected from a single user

**Photos**

- [X] Store photos from a chat
- [X] Support captions
- [X] Retrive photos at random
- [X] Internal photo backup (as opposed to just being stored on Telegram)

**Magic**

- [X] Send a command to roll an 8-ball and get back a divine answer from the bot
- [X] Luck statistics for each member of a chat group

**Birthdays**

- [X] Send the bot your birthday via the `/birthday` command and have it notify everyone a week in advance

**Administration**

- [X] Admin interface for managing quotes, chats, photos, etc.


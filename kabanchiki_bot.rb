require 'telegram/bot'
require_relative './lib/kabanchiki'
require_relative './lib/telegram_bot_api_patch'

puts "[#{Time.now}] Bot started"
Telegram::Bot::Client.run(ENV['TOKEN']) do |bot|
  bot.listen do |message|
    case message
    when Telegram::Bot::Types::CallbackQuery
      chat_id = message.message.chat.id
      game = Kabanchiki.games[chat_id]

      if message.data['🐗']
        if game
          game.new_bet(message.from.username, message.data, message.id)
        else
          bot.api.answer_callback_query(
            callback_query_id: message.id,
            text: "Эти кабанчики уже подскочили!"
          )
        end
      end

    when Telegram::Bot::Types::Message
      case message.text
      when '/bet@KabanchikiBot'
        if Kabanchiki.games[message.chat.id]
          bot.api.send_message(chat_id: message.chat.id, text: 'Кабанчики ещё на подскоке...')
        else
          game = Kabanchiki.new(bot, message.chat.id)
          Thread.start{ game.countdown }
        end
      when '/top@KabanchikiBot'
        bot.api.send_message(chat_id: message.chat.id, text: Kabanchiki.chat_top(message.chat.id))
      end
    end
  end
end
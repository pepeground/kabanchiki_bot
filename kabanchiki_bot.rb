require 'telegram/bot'
require 'logger'
require_relative 'lib/kabanchiki'

logger = Logger.new('kabanchiki_bot.log', level: :warn)
Telegram::Bot::Client.run(ENV['TOKEN'], logger: logger) do |bot|
  bot.logger.warn('Bot started')
  bot.listen do |message|

    case message
    when Telegram::Bot::Types::CallbackQuery
      if message.data['🐗']
        game = Kabanchiki.games[message.message.chat.id]
        game.new_bet(message.from.username, message.data, message.id)
      end

    when Telegram::Bot::Types::Message
      case message.text
      when /\/bet\@Kabanchiki/
        if Kabanchiki.games[message.chat.id]
          bot.api.send_message(chat_id: message.chat.id, text: 'Кабанчики ещё на подскоке...')
        else
          game = Kabanchiki.new(bot, message.chat.id)
          Thread.start{ game.countdown }
        end
      when /\/stat\@Kabanchiki/
        user = Kabanchiki.user_data(message.chat.id, message.from.username)
        text = "У #{message.from.username} "
        text << "#{(user[:balance] || Kabanchiki::BET_SIZE*10)} у.е.\n"
        text << "Ставок: #{user[:bets].to_i}  | "
        text << "Выигрышей: #{user[:right_bets].to_i}"
        if user[:bets].to_i > 0
          text << "\nПроцент: #{(user[:right_bets].to_f/user[:bets].to_f).round(2)} "
        end

        bot.api.send_message(chat_id: message.chat.id, text: text)
      when /\/top\@Kabanchiki/
        bot.api.send_message(chat_id: message.chat.id, text: Kabanchiki.chat_top(message.chat.id))
      end
    end

  end
end
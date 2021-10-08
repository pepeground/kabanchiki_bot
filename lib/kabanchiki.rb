require 'pstore'

class Kabanchiki

  class << self
    def games
      @@chats ||= {}
    end

    def store
      @@store ||= PStore.new("#{__dir__}/kabanchiki_bot.pstore")
    end

    def chat_top(chat_id)
      text = "Топ чата: \n\n"
      store.transaction(true) do
        users = (store[chat_id] || {}).sort_by{|k, v| -v}
        users.each{|u| text << "#{u.first} : #{u.last}\n"} unless users.empty?
      end
      text
    end
  end

  attr_accessor :bot, :chat_id, :bets, :kabanchiki, :started_at, :message_id, :timer

  def initialize(bot, chat_id)
    @bot = bot
    @chat_id = chat_id
    @bets = {}
    @kabanchiki = ['🐗 1', '🐗 2', '🐗 3']
    self.class.games[chat_id] = self
    @message_id = nil
  end

  def countdown
    self.message_id = bot.api.send_message(
      chat_id: chat_id,
      text: 'Кто подскочит первым?',
      reply_markup: build_buttons
    ).dig('result', 'message_id')
    3.downto(0).each do |t|
      self.timer = t
      bot.api.edit_message_reply_markup(
        chat_id: chat_id,
        message_id: message_id,
        reply_markup: build_buttons
      )
      sleep 3
    end
    race
  end

  def new_bet(username, data, callback_query_id)
    bets[username] = data
    bot.api.answer_callback_query(
      callback_query_id: callback_query_id,
      text: "Кабанчик #{data} выбран!"
    )
  end

  def race
    places = kabanchiki.shuffle.to_h{|i| [i, 4]}
    lap = 1
    first_touch = false

    until first_touch do
      places.each do |kaban, place|
        if lap > 1
          if first_touch
            places[kaban] -= [1, 1, 1, 0, 0].sample if place > 2
          else
            places[kaban] -= [1, 1, 1, 0, 0].sample
          end
        end
        first_touch = true if (places[kaban] < 2 && !first_touch)
      end
      bot.api.edit_message_text(
        chat_id: chat_id,
        message_id: message_id,
        text: render_places(places)
      )
      sleep 1.5
      lap += 1
    end

    award places
  end

  def render_places(places)
    text =  "Погнали!\n"
    kabanchiki.each do |kaban|
      text << "|"
      4.times do |t|
        text << (places[kaban] === t + 1 ? kaban : ' . ')
      end
      text << "\n"
    end
    text
  end

  def award(places)
    winner = places.sort_by{|k, v| v}.first.first
    result = render_places(places)
    result << "\nКабанчик #{winner} подскочил первым!"

    right_bets = []
    bets.each do |user, bet|
      right_bets << user if bet === winner
    end

    unless right_bets.empty?
      result << "\n\n"
      result << right_bets.join(', ')
      result << ' поставил(и) на правильного кабанчика!'
      update_chat_top(right_bets)
    end

    bot.api.edit_message_text(chat_id: chat_id, message_id: message_id, text: result)
    Kabanchiki.games[chat_id] = nil
  end

  def build_buttons
    buttons = []
    kabanchiki.each do |kaban|
      text = bets.size > 0 ? "#{kaban} (#{bets.values.count(kaban)})" : kaban
      buttons << Telegram::Bot::Types::InlineKeyboardButton.new(
        text: text,
        callback_data: kaban
      )
    end

    buttons << Telegram::Bot::Types::InlineKeyboardButton.new(
      text: "Кабанчики метнутся через #{timer}",
      callback_data: 'kabanchiki_timer'
    )
    Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: buttons)
  end

  def update_chat_top(users)
    store = self.class.store
    store.transaction do
      new_top = {}
      old_top =  store[chat_id] || {}
      users.each do |user|
        new_top[user] = old_top[user].to_i + 1
      end
      store[chat_id] = old_top.merge(new_top)
    end
  end

end

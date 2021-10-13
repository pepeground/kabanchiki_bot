require 'pstore'

class Kabanchiki
  BET_COST = 10.freeze

  class << self

    def games
      @@games ||= {}
    end

    def last_pot
      @@last_pot ||= {}
    end

    def store
      @@store ||= PStore.new('kabanchiki_bot.pstore')
    end

    def user_data(chat_id, username)
      store.transaction(true) do
        store.fetch(chat_id, {}).fetch(username, {})
      end
    end

    def chat_top(chat_id)
      text = "Топ 10 чата: \n\n"
      store.transaction(true) do
        users = (store[chat_id] || {}).sort_by{|k, v| -v[:balance]}.first(10)
        users.each{|u| text << "#{u.first} (#{u.last[:balance]} у.е.)\n"} unless users.empty?
      end
      text
    end
  end

  attr_accessor :bot, :chat_id, :bets, :kabanchiki, :message_id, :timer

  def initialize(bot, chat_id)
    @bot = bot
    @chat_id = chat_id
    @bets = {}
    @kabanchiki = ['🐗 1', '🐗 2', '🐗 3']
    self.class.games[chat_id] = self
    @message_id = nil
  end

  def api(method, **params)
    begin
      bot.api.send(method, params)
    rescue => e
      bot.logger.error("Telegram error! #{e.message}") unless e.error_code === 400
    end
  end

  def countdown
    self.message_id = api(
      :send_message,
      chat_id: chat_id,
      text: "Кто подскочит первым?\n(ставка - #{BET_COST} у.е.)",
      reply_markup: build_buttons
    ).dig('result', 'message_id')
    3.downto(0).each do |t|
      self.timer = t
      api(
        :edit_message_reply_markup,
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
    api(
      :answer_callback_query,
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
      api(
        :edit_message_text,
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
    pot, prize = update_balance(right_bets)

    unless right_bets.empty?
      result << "\n\n"
      result << "Cтавок: #{bets.size} Общак: #{pot} у.е.\n"
      result << right_bets.join(', ')
      if right_bets.size > 1
        result << ' поставили на правильного кабанчика и получают по '
      else
        result << ' поставил на правильного кабанчика и получает '
      end
      result << "#{prize} у.е."
    end

    api(:edit_message_text,chat_id: chat_id, message_id: message_id, text: result)
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

  def update_balance(winners)
    pot = bets.size * BET_COST
    pot += self.class.last_pot[chat_id].to_i
    if winners.empty?
      prize = 0
      self.class.last_pot[chat_id] = pot
    else
      prize = (pot.to_f / winners.size).round
      self.class.last_pot[chat_id] = nil
    end

    store = self.class.store
    store.transaction do
      old_data = store[chat_id] || {}
      new_data = {}

      bets.each do |user, bet|
        new_data[user] = {
          bets: old_data.dig(user, :bets).to_i + 1,
          right_bets: old_data.dig(user, :right_bets).to_i,
          balance: (old_data.dig(user, :balance) || (BET_COST * 10)) - BET_COST
        }

        if winners.include?(user)
          new_data[user][:right_bets] += 1
          new_data[user][:balance] += prize
        end
      end

      store[chat_id] = old_data.merge(new_data)
    end

    [pot, prize]
  end

end

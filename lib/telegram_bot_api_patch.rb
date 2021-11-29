module Telegram
  module Bot
    class Api
      def call(endpoint, raw_params = {})
        params = build_params(raw_params)
        response = conn.post("/bot#{token}/#{endpoint}", params)
        if response.status == 200
          JSON.parse(response.body)
        else
          puts "[#{Time.now}] API error: #{response.status} #{response.body}"
        end
      end
    end
  end
end

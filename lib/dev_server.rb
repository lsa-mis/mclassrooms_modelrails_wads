# frozen_string_literal: true

module DevServer
  def self.port(env = ENV)
    env.fetch("DEV_SERVER_PORT") { env.fetch("PORT", 3000) }.to_i
  end
end

# frozen_string_literal: true

require "rails_helper"
require "dev_server"

RSpec.describe DevServer do
  describe ".port" do
    it "is the web server's port that bin/dev recorded, whatever PORT foreman gave this process" do
      expect(described_class.port({ "DEV_SERVER_PORT" => "3000", "PORT" => "3200" })).to eq(3000)
    end

    it "falls back to PORT when the server was started without bin/dev" do
      expect(described_class.port({ "PORT" => "3001" })).to eq(3001)
    end

    it "is 3000 when neither is set" do
      expect(described_class.port({})).to eq(3000)
    end
  end

  it "is recorded by bin/dev before foreman hands each process its own PORT" do
    script = Rails.root.join("bin/dev").read

    expect(script).to match(/^export DEV_SERVER_PORT="\$PORT"$/)
    expect(script.index("DEV_SERVER_PORT")).to be < script.index("exec foreman")
  end

  it "is where development's mailer links take their port" do
    config = Rails.root.join("config/environments/development.rb").read

    expect(config).not_to include('ENV.fetch("PORT"')
    expect(config.scan("DevServer.port").size).to eq(2)
  end
end

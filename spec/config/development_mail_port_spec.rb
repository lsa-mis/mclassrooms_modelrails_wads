# frozen_string_literal: true

require "rails_helper"
require "open3"

RSpec.describe "Development mail links", type: :config do
  def boot_development(env)
    script = "puts Rails.application.config.action_mailer.default_url_options.to_json, Passkeys.origin"
    clean = { "RAILS_ENV" => "development", "CODESPACES" => nil, "WEBAUTHN_ORIGIN" => nil, "DEV_SERVER_PORT" => nil, "PORT" => nil }
    output, status = Open3.capture2e(clean.merge(env), "bin/rails", "runner", script, chdir: Rails.root.to_s)
    expect(status).to be_success, output
    url_options, passkey_origin = output.lines.last(2).map(&:strip)
    [ JSON.parse(url_options, symbolize_names: true), passkey_origin ]
  end

  it "targets the web server's port in a process foreman gave a port of its own" do
    url_options, passkey_origin = boot_development("DEV_SERVER_PORT" => "3000", "PORT" => "3200")

    expect(url_options).to eq(host: "localhost", port: 3000)
    expect(passkey_origin).to eq("http://localhost:3000")
  end

  it "targets the forwarded web port in a Codespace" do
    url_options, = boot_development(
      "DEV_SERVER_PORT" => "3000", "PORT" => "3200", "CODESPACES" => "true",
      "CODESPACE_NAME" => "cs", "GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN" => "app.github.dev"
    )

    expect(url_options).to eq(host: "cs-3000.app.github.dev", protocol: "https")
  end

  it "follows PORT when the server runs without bin/dev" do
    url_options, = boot_development("PORT" => "3001")

    expect(url_options).to eq(host: "localhost", port: 3001)
  end
end

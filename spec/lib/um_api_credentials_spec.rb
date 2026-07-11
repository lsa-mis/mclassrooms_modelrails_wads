require "rails_helper"

RSpec.describe UmApiCredentials do
  describe ".install!" do
    let(:env) { {} }

    it "bridges the legacy buildings_* credential keys into UM_API_* ENV, with URL defaults" do
      creds = { buildings_client_id: "cid", buildings_client_secret: "csecret" }

      described_class.install!(credentials: creds, env: env)

      expect(env["UM_API_CLIENT_ID"]).to eq("cid")
      expect(env["UM_API_CLIENT_SECRET"]).to eq("csecret")
      expect(env["UM_API_TOKEN_URL"]).to eq(described_class::DEFAULT_TOKEN_URL)
      expect(env["UM_API_BASE_URL"]).to eq(described_class::DEFAULT_BASE_URL)
    end

    it "prefers scope-neutral client_id/client_secret over the legacy buildings_* keys" do
      creds = { client_id: "new", buildings_client_id: "old",
                client_secret: "ns", buildings_client_secret: "os" }

      described_class.install!(credentials: creds, env: env)

      expect(env["UM_API_CLIENT_ID"]).to eq("new")
      expect(env["UM_API_CLIENT_SECRET"]).to eq("ns")
    end

    it "never overrides an explicit ENV value (a dev .env / Kamal secret wins)" do
      env["UM_API_CLIENT_ID"] = "from_env"
      env["UM_API_BASE_URL"] = "https://override.example"

      described_class.install!(credentials: { buildings_client_id: "from_creds" }, env: env)

      expect(env["UM_API_CLIENT_ID"]).to eq("from_env")
      expect(env["UM_API_BASE_URL"]).to eq("https://override.example")
    end

    it "uses token_url/base_url from credentials when they are provided" do
      creds = { buildings_client_id: "x", buildings_client_secret: "y",
                token_url: "https://t.example/token", base_url: "https://b.example/api" }

      described_class.install!(credentials: creds, env: env)

      expect(env["UM_API_TOKEN_URL"]).to eq("https://t.example/token")
      expect(env["UM_API_BASE_URL"]).to eq("https://b.example/api")
    end

    it "no-ops when no um_api credentials are configured" do
      expect { described_class.install!(credentials: nil, env: env) }.not_to raise_error
      expect(env).to be_empty
    end

    it "does not set a client key whose credential value is blank" do
      described_class.install!(credentials: { buildings_client_id: "" }, env: env)

      expect(env).not_to have_key("UM_API_CLIENT_ID")
    end
  end
end

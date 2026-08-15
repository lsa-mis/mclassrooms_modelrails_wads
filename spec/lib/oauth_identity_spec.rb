require "rails_helper"

RSpec.describe OauthIdentity do
  def auth_hash(overrides = {})
    OmniAuth::AuthHash.new({
      provider: "google_oauth2",
      uid: "uid-123",
      info: { email: "person@example.com", first_name: "Ada", last_name: "Lovelace", image: "https://img/a.png" },
      credentials: { token: "tok", refresh_token: "rtok", expires_at: 1.hour.from_now.to_i }
    }.deep_merge(overrides))
  end

  it "normalizes the provider and exposes the human label" do
    identity = described_class.new(auth_hash)
    expect(identity.provider).to eq(OmniauthAdapters.normalize_provider("google_oauth2"))
    expect(identity.provider_name).to eq(Authentication.display_name_for(identity.provider))
  end

  it "exposes uid and email" do
    identity = described_class.new(auth_hash)
    expect(identity.uid).to eq("uid-123")
    expect(identity.email).to eq("person@example.com")
  end

  describe "#email_verified?" do
    it "is true when the provider omits the field (e.g. GitHub)" do
      expect(described_class.new(auth_hash).email_verified?).to be(true)
    end

    it "is false only when the provider explicitly reports email_verified: false" do
      identity = described_class.new(auth_hash(info: { email_verified: false }))
      expect(identity.email_verified?).to be(false)
    end
  end

  describe "name fallbacks" do
    it "uses first/last name when present" do
      identity = described_class.new(auth_hash)
      expect([ identity.first_name, identity.last_name ]).to eq([ "Ada", "Lovelace" ])
    end

    it "splits a single name field into first/last" do
      identity = described_class.new(auth_hash(info: { first_name: nil, last_name: nil, name: "Grace Hopper" }))
      expect([ identity.first_name, identity.last_name ]).to eq([ "Grace", "Hopper" ])
    end

    it "falls back to 'User' when the provider supplies no usable name" do
      # OmniAuth's InfoHash computes `name` from first/last/nickname/email, so
      # the bare fallback only surfaces when all of those are blank too.
      blank = described_class.new(auth_hash(info: { first_name: nil, last_name: nil, name: nil, nickname: nil, email: nil }))
      expect([ blank.first_name, blank.last_name ]).to eq([ "User", "User" ])
    end
  end

  describe "#auth_attrs" do
    it "carries credentials and includes the avatar only when present" do
      attrs = described_class.new(auth_hash).auth_attrs
      expect(attrs[:oauth_token]).to eq("tok")
      expect(attrs[:oauth_refresh_token]).to eq("rtok")
      expect(attrs[:oauth_expires_at]).to be_within(1.second).of(Time.at(auth_hash.credentials.expires_at))
      expect(attrs[:avatar_url]).to eq("https://img/a.png")
    end

    it "omits avatar_url when the provider supplies no image" do
      attrs = described_class.new(auth_hash(info: { image: nil })).auth_attrs
      expect(attrs).not_to have_key(:avatar_url)
    end
  end
end

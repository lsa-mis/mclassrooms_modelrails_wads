require "rails_helper"

# Exercises the shared atomic-consume contract directly, through MagicLinkToken
# as a representative host. The per-model specs (magic_link_token,
# reauthentication_challenge, webauthn_challenge) cover their own wrappers.
RSpec.describe Consumable do
  let(:email) { "consumable@example.com" }

  def token_digest_for(plaintext)
    MagicLinkToken.digest(plaintext)
  end

  it "consumes exactly one matching, unexpired, unconsumed row" do
    token = MagicLinkToken.create_for_email(email)
    digest = token_digest_for(token)

    expect(MagicLinkToken.consume_matching(token_digest: digest)).to eq(1)
  end

  it "is single-use — a second consume of the same row consumes nothing" do
    token = MagicLinkToken.create_for_email(email)
    digest = token_digest_for(token)

    expect(MagicLinkToken.consume_matching(token_digest: digest)).to eq(1)
    expect(MagicLinkToken.consume_matching(token_digest: digest)).to eq(0)
  end

  it "consumes nothing once the row has expired" do
    token = MagicLinkToken.create_for_email(email)
    digest = token_digest_for(token)

    travel 16.minutes do
      expect(MagicLinkToken.consume_matching(token_digest: digest)).to eq(0)
    end
  end
end

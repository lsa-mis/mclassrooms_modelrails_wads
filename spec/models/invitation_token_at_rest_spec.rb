# frozen_string_literal: true

require "rails_helper"

# #953: the invitation token is a bearer credential rebuilt into URLs days
# after creation (expiring-soon reminder, notification mailer), so it cannot be
# a digest like MagicLinkToken's. Deterministic encryption keeps find_by(token:)
# and the unique index working while the stored bytes are useless without the key.
RSpec.describe Invitation, "token at rest" do
  let(:invitation) { create(:invitation) }

  it "is declared encrypted, deterministically" do
    expect(Invitation.encrypted_attributes).to include(:token)
    expect(Invitation.type_for_attribute("token")).to be_deterministic
  end

  it "stores ciphertext and still finds the row by plaintext" do
    raw = Invitation.connection.select_value(
      Invitation.sanitize_sql([ "SELECT token FROM invitations WHERE id = ?", invitation.id ])
    )

    expect(raw).not_to eq(invitation.token)
    expect(Invitation.find_by(token: invitation.token)).to eq(invitation)
  end
end

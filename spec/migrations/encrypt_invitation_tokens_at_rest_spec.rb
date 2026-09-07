# frozen_string_literal: true

require "rails_helper"
require_relative "../../db/migrate/20260903115906_encrypt_invitation_tokens_at_rest"

RSpec.describe EncryptInvitationTokensAtRest do
  let(:raw_invitations) { Class.new(ActiveRecord::Base) { self.table_name = "invitations" } }
  let(:raw_authentications) { Class.new(ActiveRecord::Base) { self.table_name = "authentications" } }
  let(:migration) { described_class.new }

  it "encrypts plaintext tokens in place, finds them by plaintext, reverses, and is idempotent" do
    invitation = create(:invitation)
    plaintext = invitation.token
    raw_invitations.where(id: invitation.id).update_all(token: plaintext)     # force plaintext at rest
    authentication = create(:authentication)
    raw_authentications.where(id: authentication.id).update_all(pending_invitation_token: plaintext)

    # Fix round 1, item 1: prove the setup really bypassed encryption, so this
    # example cannot pass on a row `up` merely (correctly) skips as already-encrypted.
    expect(raw_invitations.find(invitation.id).token).to eq(plaintext)
    expect(raw_authentications.find(authentication.id).pending_invitation_token).to eq(plaintext)

    ActiveRecord::Migration.suppress_messages { migration.up }

    expect(raw_invitations.find(invitation.id).token).not_to eq(plaintext)
    expect(Invitation.find_by(token: plaintext)).to eq(invitation)
    expect(Authentication.find(authentication.id).pending_invitation_token).to eq(plaintext)

    encrypted_once = raw_invitations.find(invitation.id).token
    ActiveRecord::Migration.suppress_messages { migration.up }
    expect(raw_invitations.find(invitation.id).token).to eq(encrypted_once)

    ActiveRecord::Migration.suppress_messages { migration.down }
    expect(raw_invitations.find(invitation.id).token).to eq(plaintext)
    expect(raw_authentications.find(authentication.id).pending_invitation_token).to eq(plaintext)
  end

  # Fix round 1, item 6: with support_unencrypted_data on, a plaintext row
  # "decrypts" without raising (Rails hands the plaintext back), so `decrypts?`
  # would misread every never-migrated row as already-encrypted and `up` would
  # silently skip it — reporting success while leaving bearer tokens in the
  # clear. `up` must refuse to run in that configuration instead.
  it "refuses to run under support_unencrypted_data, before touching any row" do
    invitation = create(:invitation)
    plaintext = invitation.token
    raw_invitations.where(id: invitation.id).update_all(token: plaintext)
    allow(ActiveRecord::Encryption.config).to receive(:support_unencrypted_data).and_return(true)

    expect { ActiveRecord::Migration.suppress_messages { migration.up } }
      .to raise_error(/support_unencrypted_data must be off/)

    expect(raw_invitations.find(invitation.id).token).to eq(plaintext) # untouched
  end
end

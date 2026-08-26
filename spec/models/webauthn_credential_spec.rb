require "rails_helper"

RSpec.describe WebauthnCredential do
  let(:credential) { create(:webauthn_credential, sign_count: 5) }

  it "advances sign_count and records last_used_at" do
    credential.advance_sign_count!(6)
    expect(credential.reload.sign_count).to eq(6)
    expect(credential.last_used_at).to be_present
  end

  it "raises ClonedAuthenticator when the count does not advance" do
    expect { credential.advance_sign_count!(5) }.to raise_error(Passkeys::ClonedAuthenticator)
    expect(credential.reload.sign_count).to eq(5)
  end

  # Platform passkeys (Apple/Google) always report sign_count 0 — per WebAuthn
  # §7.2 that means "counter unsupported", NOT a clone. Must accept it on every
  # sign-in, or counter-less authenticators can never sign in twice.
  it "accepts a zero sign_count without flagging a clone (counter-less passkey)" do
    zero = create(:webauthn_credential, sign_count: 0)
    expect { zero.advance_sign_count!(0) }.not_to raise_error
    expect(zero.reload.last_used_at).to be_present
    expect(zero.sign_count).to eq(0)
  end

  it "does not lower a stored counter when the authenticator reports zero" do
    credential.advance_sign_count!(0)
    expect(credential.reload.sign_count).to eq(5)
    expect(credential.last_used_at).to be_present
  end

  it "is discardable (kept scope excludes discarded)" do
    credential.discard!
    expect(WebauthnCredential.kept).not_to include(credential)
  end

  describe "audit trail" do
    let(:credential) { create(:webauthn_credential) }

    it "writes user.passkey_added on create, in-transaction" do
      expect { create(:webauthn_credential) }
        .to change { ActivityLog.where(action: "user.passkey_added", visibility: "personal").count }.by(1)
    end

  # SQLite serializes the two writers but does not make the second re-read.
  # discarded_at_before_last_save is in-memory dirty tracking: it distinguishes
  # a repeat discard! on the SAME object, and says nothing about a second
  # request holding its own stale copy (#826). Two instances loaded while the
  # record was kept reproduce that deterministically, no threads needed.
  it "writes one removal row when two separately-loaded instances both discard" do
    credential # Ruling R7: materialize before the count block.
    first = WebauthnCredential.find(credential.id)
    second = WebauthnCredential.find(credential.id)

    expect {
      first.discard!
      second.discard!
    }.to change { ActivityLog.where(action: "user.passkey_removed").count }.by(1)
  end

  it "reports whether it won the discard, so a loser can be told apart" do
    credential
    first = WebauthnCredential.find(credential.id)
    second = WebauthnCredential.find(credential.id)

    expect(first.discard!).to be(true)
    expect(second.discard!).to be(false)
  end

  it "writes user.passkey_removed on discard" do
      credential
      expect { credential.discard! }
        .to change { ActivityLog.where(action: "user.passkey_removed", trackable: credential.user).count }.by(1)
    end

    it "does not write a row when undiscarding a passkey" do
      credential.discard!
      expect { credential.undiscard! }.not_to change { ActivityLog.count }
    end

    # discard! is an unconditional update!, so a second call restamps
    # discarded_at and looks like a fresh removal. This row is the only record
    # that a passkey was removed — a duplicate misreports one removal as two.
    it "does not write a second row when an already-discarded passkey is discarded again" do
      credential.discard!
      expect { credential.discard! }
        .not_to change { ActivityLog.where(action: "user.passkey_removed").count }
    end

    it "writes again when a restored passkey is removed a second time" do
      credential.discard!
      credential.undiscard!
      expect { credential.discard! }
        .to change { ActivityLog.where(action: "user.passkey_removed", trackable: credential.user).count }.by(1)
    end

    it "does not write a row when advancing sign_count" do
      cred = create(:webauthn_credential, sign_count: 5)
      expect { cred.advance_sign_count!(6) }.not_to change { ActivityLog.count }
    end

    # The removal path's strict-tier guarantee. discard! now claims the
    # transition with a CAS and audits inside the same transaction (#826), so
    # this proves the claim rolls back too — not just that the raise escaped.
    it "rolls back the discard when the removal audit write fails" do
      credential # Ruling R7: materialize before the stub.
      allow(ActivityLog).to receive(:record_security_event!)
        .with(hash_including(action: "user.passkey_removed"))
        .and_raise(ActiveRecord::StatementInvalid, "boom")

      expect { credential.discard! }.to raise_error(ActiveRecord::StatementInvalid)

      expect(credential.reload.discarded_at).to be_nil
      expect(WebauthnCredential.kept).to include(credential)
    end

    it "rolls back the credential when the audit write fails" do
      # Ruling R7 (spec/models/user_spec.rb carries the same precedent):
      # materialize the user BEFORE installing the stub. Creating a
      # WebauthnCredential via the factory also creates a User, whose
      # onboarding drives audit writes through other paths — stub first and
      # this example could pass for an incidental reason instead of proving
      # the credential's own rollback.
      user = create(:user)
      allow(ActivityLog).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")
      expect { create(:webauthn_credential, user: user) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(WebauthnCredential.count).to eq(0)
    end
  end
end

require "rails_helper"

RSpec.describe Authentication, type: :model do
  describe "validations" do
    it "requires a provider" do
      auth = build(:authentication, provider: nil)
      expect(auth).not_to be_valid
    end

    it "requires a uid" do
      auth = build(:authentication, uid: nil)
      expect(auth).not_to be_valid
    end

    it "enforces unique provider per user" do
      user = create(:user)
      create(:authentication, user: user, provider: "google", uid: "123")
      duplicate = build(:authentication, user: user, provider: "google", uid: "456")
      expect(duplicate).not_to be_valid
    end

    it "allows same provider for different users" do
      create(:authentication, provider: "google", uid: "123")
      other = build(:authentication, provider: "google", uid: "456")
      expect(other).to be_valid
    end

    describe "avatar_url format" do
      it "accepts https URLs" do
        auth = build(:authentication, avatar_url: "https://example.com/avatar.png")
        expect(auth).to be_valid
      end

      it "allows blank avatar_url" do
        auth = build(:authentication, avatar_url: nil)
        expect(auth).to be_valid
      end

      it "rejects http (non-TLS) URLs" do
        auth = build(:authentication, avatar_url: "http://example.com/avatar.png")
        expect(auth).not_to be_valid
      end

      it "rejects URLs with embedded whitespace (prevents newline injection)" do
        auth = build(:authentication, avatar_url: "https://example.com\njavascript:alert(1)")
        expect(auth).not_to be_valid
      end

      it "rejects javascript: scheme" do
        auth = build(:authentication, avatar_url: "javascript:alert(1)")
        expect(auth).not_to be_valid
      end
    end
  end

  describe "providers" do
    it "supports email provider" do
      auth = build(:authentication, provider: "email")
      expect(auth.email?).to be true
    end

    it "supports google provider" do
      auth = build(:authentication, provider: "google")
      expect(auth.google?).to be true
    end

    it "supports github provider" do
      auth = build(:authentication, provider: "github")
      expect(auth.github?).to be true
    end
  end

  describe "email verification token" do
    let(:auth) { create(:authentication, provider: "email", verified_at: nil) }

    it "round-trips a signed token back to the same record" do
      token = auth.generate_token_for(:email_verification)
      expect(Authentication.find_by_token_for(:email_verification, token)).to eq(auth)
    end

    it "rejects a tampered or unknown token" do
      expect(Authentication.find_by_token_for(:email_verification, "not-a-real-token")).to be_nil
    end

    it "expires the token after TOKEN_LIFETIME" do
      token = auth.generate_token_for(:email_verification)
      travel(Authentication::TOKEN_LIFETIME + 1.minute) do
        expect(Authentication.find_by_token_for(:email_verification, token)).to be_nil
      end
    end

    it "invalidates the token once the auth is verified (single-use)" do
      token = auth.generate_token_for(:email_verification)
      auth.verify!
      expect(Authentication.find_by_token_for(:email_verification, token)).to be_nil
    end
  end

  describe "#verified?" do
    it "returns true when verified_at is present" do
      auth = create(:authentication, :verified)
      expect(auth).to be_verified
    end

    it "returns false when verified_at is nil" do
      auth = create(:authentication)
      expect(auth).not_to be_verified
    end
  end

  describe ".oauth scope" do
    it "returns only non-email providers" do
      email_auth = create(:authentication, provider: "email")
      google_auth = create(:authentication, :google)
      expect(Authentication.oauth).to include(google_auth)
      expect(Authentication.oauth).not_to include(email_auth)
    end
  end
end

RSpec.describe Authentication, type: :model do
  describe "verification state" do
    let(:auth) { build(:authentication) }

    describe "#verified?" do
      it "is true when verified_at is present" do
        auth.verified_at = Time.current
        expect(auth.verified?).to be true
      end

      it "is false when verified_at is nil" do
        auth.verified_at = nil
        expect(auth.verified?).to be false
      end
    end

    describe "#pending?" do
      it "is true when verified_at is nil" do
        auth.verified_at = nil
        expect(auth.pending?).to be true
      end

      it "is false when verified_at is set" do
        auth.verified_at = Time.current
        expect(auth.pending?).to be false
      end
    end

    describe "#verify!" do
      let(:auth) { create(:authentication, verified_at: nil) }

      it "sets verified_at to now" do
        freeze_time do
          auth.verify!
          expect(auth.verified_at).to eq(Time.current)
        end
      end
    end
  end

  describe "scopes" do
    let!(:verified) { create(:authentication, verified_at: Time.current) }
    let!(:pending)  { create(:authentication, verified_at: nil) }

    it ".verified returns rows with verified_at set" do
      expect(Authentication.verified).to include(verified)
      expect(Authentication.verified).not_to include(pending)
    end

    it ".pending returns rows with verified_at nil" do
      expect(Authentication.pending).to include(pending)
      expect(Authentication.pending).not_to include(verified)
    end
  end

  describe ".display_name_for" do
    it "returns 'GitHub' for github (not 'Github')" do
      expect(Authentication.display_name_for("github")).to eq("GitHub")
    end

    it "returns 'Google' for google" do
      expect(Authentication.display_name_for("google")).to eq("Google")
    end

    it "returns 'Email' for email" do
      expect(Authentication.display_name_for("email")).to eq("Email")
    end

    it "falls back to titleize for unknown providers" do
      expect(Authentication.display_name_for("unknown_provider")).to eq("Unknown Provider")
    end
  end

  describe "#display_provider" do
    it "uses the class-level display map" do
      auth = build(:authentication, provider: "github")
      expect(auth.display_provider).to eq("GitHub")
    end
  end

  describe "#only_verified_remaining?" do
    let(:user) { create(:user) }

    context "when this is the only verified auth for the user" do
      let!(:auth) { user.authentications.create!(provider: "email", uid: user.email_address, email: user.email_address, verified_at: Time.current) }

      it "returns true" do
        expect(auth.only_verified_remaining?).to be true
      end
    end

    context "when other verified auths exist for the user" do
      let!(:auth) { user.authentications.create!(provider: "email", uid: user.email_address, email: user.email_address, verified_at: Time.current) }
      let!(:other_verified) { user.authentications.create!(provider: "google", uid: "g-1", email: "test@example.com", verified_at: Time.current) }

      it "returns false" do
        expect(auth.only_verified_remaining?).to be false
      end
    end

    context "when this auth is itself unverified" do
      let!(:auth) { user.authentications.create!(provider: "email", uid: user.email_address, email: user.email_address, verified_at: nil) }

      it "returns false (the auth being deleted isn't a verified auth, so deletion can't reduce the verified count)" do
        expect(auth.only_verified_remaining?).to be false
      end
    end
  end

  describe "#claim_pending_invitation!" do
    let(:user) { create(:user) }
    let(:authentication) { create(:authentication, user: user, pending_invitation_token: nil) }

    it "is a no-op when pending_invitation_token is blank" do
      expect {
        authentication.claim_pending_invitation!(user)
      }.not_to change(user.workspaces, :count)
    end

    it "clears the token and returns nil when token matches no invitation" do
      authentication.update!(pending_invitation_token: "no-such-token-anywhere")
      authentication.claim_pending_invitation!(user)
      expect(authentication.reload.pending_invitation_token).to be_nil
    end

    it "accepts the invitation and clears the token on success" do
      invitation = create(:invitation, email: user.email_address)
      authentication.update!(pending_invitation_token: invitation.token)

      authentication.claim_pending_invitation!(user)

      expect(invitation.reload).to be_accepted
      expect(authentication.reload.pending_invitation_token).to be_nil
      expect(user.workspaces).to include(invitation.invitable)
    end

    it "raises Invitation::NotAcceptable and does NOT clear the token when invitation is stale" do
      invitation = create(:invitation, :expired, email: user.email_address)
      authentication.update!(pending_invitation_token: invitation.token)

      expect {
        authentication.claim_pending_invitation!(user)
      }.to raise_error(Invitation::NotAcceptable)

      expect(authentication.reload.pending_invitation_token).to eq(invitation.token)
    end

    it "raises EmailMismatch and clears the token when the invitation is for a different email" do
      invitation = create(:invitation, email: "invited@example.com")
      authentication.update!(pending_invitation_token: invitation.token)
      # `user`'s email differs from the invitation's address.

      expect {
        authentication.claim_pending_invitation!(user)
      }.to raise_error(Invitation::EmailMismatch)

      expect(invitation.reload).to be_pending
      expect(authentication.reload.pending_invitation_token).to be_nil
    end
  end

  describe "#claim_pending_join_link!" do
    let(:user) { create(:user) }
    let(:authentication) { create(:authentication, user: user, pending_join_link_token: nil) }
    let(:workspace) { create(:workspace, personal: false, join_policy: "open_link") }
    let!(:member_role) {
      Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r|
        r.name = "Member"
        r.permissions = {}
      }
    }
    let(:link) { create(:workspace_join_link, workspace: workspace, created_by: create(:user)) }

    before do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
    end

    it "is a no-op when pending_join_link_token is blank" do
      expect {
        authentication.claim_pending_join_link!(user)
      }.not_to change(user.workspaces, :count)
    end

    it "clears the token and returns nil when the token matches no link" do
      authentication.update!(pending_join_link_token: "no-such-token")
      authentication.claim_pending_join_link!(user)
      expect(authentication.reload.pending_join_link_token).to be_nil
    end

    it "admits the user as Member and clears the token on success" do
      authentication.update!(pending_join_link_token: link.token)

      authentication.claim_pending_join_link!(user)

      expect(user.workspaces).to include(workspace)
      expect(workspace.memberships.find_by!(user: user).role.slug).to eq("member")
      expect(authentication.reload.pending_join_link_token).to be_nil
    end

    it "silently clears the token when the link has been revoked" do
      link.revoke!
      authentication.update!(pending_join_link_token: link.token)

      expect {
        authentication.claim_pending_join_link!(user)
      }.not_to change(user.workspaces, :count)
      expect(authentication.reload.pending_join_link_token).to be_nil
    end

    it "silently clears the token when the workspace's policy is no longer open_link" do
      authentication.update!(pending_join_link_token: link.token)
      workspace.update!(join_policy: "invite")

      expect {
        authentication.claim_pending_join_link!(user)
      }.not_to change(user.workspaces, :count)
      expect(authentication.reload.pending_join_link_token).to be_nil
    end

    it "clears the spent token even when admission fails because the workspace is at capacity" do
      workspace.update!(max_members: 1)
      create(:membership, workspace: workspace, user: create(:user), role: member_role)
      authentication.update!(pending_join_link_token: link.token)

      expect {
        authentication.claim_pending_join_link!(user)
      }.to raise_error(ActiveRecord::RecordInvalid, /at capacity/i)

      # The token represents a one-shot claim. A capacity failure is terminal
      # for this attempt (verify never retries), so the token must not survive
      # the rollback and linger as orphaned state.
      expect(authentication.reload.pending_join_link_token).to be_nil
    end
  end

  describe "broadcasting" do
    let(:user) { create(:user) }
    # Turbo broadcasts to the stream name computed by stream_name_from([user, :authentications]),
    # which concatenates each element's to_gid_param (or to_param) with ":".
    let(:stream_name) { [ user, :authentications ].map { |s| s.try(:to_gid_param) || s.to_param }.join(":") }

    it "broadcasts a refresh to the user's authentications stream on create" do
      expect {
        user.authentications.create!(provider: "google", uid: "g-broadcast-1",
          email: "test@example.com", verified_at: Time.current)
      }.to have_broadcasted_to(stream_name)
    end

    it "broadcasts a refresh on update (e.g., verify!)" do
      auth = user.authentications.create!(provider: "google", uid: "g-broadcast-2",
        email: "test@example.com", verified_at: nil)

      expect {
        auth.verify!
      }.to have_broadcasted_to(stream_name)
    end

    it "broadcasts a refresh on destroy (cancel pending or unlink)" do
      auth = user.authentications.create!(provider: "google", uid: "g-broadcast-3",
        email: "test@example.com", verified_at: Time.current)

      expect {
        auth.destroy!
      }.to have_broadcasted_to(stream_name)
    end
  end
end

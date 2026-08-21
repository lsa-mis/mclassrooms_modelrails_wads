require "rails_helper"

RSpec.describe OauthLink do
  def google_hash(uid: "uid-123", email: "person@example.com", email_verified: nil,
                  image: nil, token: "tok")
    info = { email: email, first_name: "Pat", last_name: "Doe" }
    info[:email_verified] = email_verified unless email_verified.nil?
    info[:image] = image if image
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: info,
      credentials: { token: token, refresh_token: "rtok", expires_at: 1.hour.from_now.to_i }
    )
  end

  describe "existing identity (provider+uid already linked)" do
    let!(:owner) { create(:user, email_address: "owner@example.com") }
    let!(:auth) do
      owner.authentications.create!(
        provider: "google", uid: "uid-1", email: "owner@example.com", verified_at: Time.current
      )
    end

    it "returns :signed_in with the identity's user and refreshes OAuth credentials" do
      outcome = described_class.new(google_hash(uid: "uid-1", token: "fresh")).claim

      expect(outcome.code).to eq(:signed_in)
      expect(outcome.user).to eq(owner)
      expect(auth.reload.oauth_token).to eq("fresh")
    end

    it "returns :collision and alerts the owner when a different signed-in user presents the identity" do
      eve = create(:user)

      outcome = nil
      expect {
        outcome = described_class.new(google_hash(uid: "uid-1"), actor: eve).claim
      }.to have_enqueued_mail(AuthenticationMailer, :collision_alert).with(owner, "Google")

      expect(outcome.code).to eq(:collision)
      expect(outcome.provider_name).to eq("Google")
    end

    it "returns :verification_resent with a fresh email when the identity is still pending" do
      auth.update!(verified_at: nil)

      outcome = nil
      expect {
        outcome = described_class.new(google_hash(uid: "uid-1")).claim
      }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)

      expect(outcome.code).to eq(:verification_resent)
      expect(outcome.email).to eq(auth.email)
      expect(auth.reload.verified_at).to be_nil
    end

    it "returns :failed when refreshing credentials trips validation (provider-sent bad avatar URL)" do
      outcome = described_class.new(google_hash(uid: "uid-1", image: "notaurl")).claim

      expect(outcome.code).to eq(:failed)
    end
  end

  describe "signed-in user linking a new provider" do
    let(:actor) do
      create(:user, email_address: "actor@example.com").tap do |u|
        u.authentications.create!(provider: "email", uid: u.email_address, verified_at: Time.current)
      end
    end

    it "returns :already_linked when the provider is already verified for this user" do
      actor.authentications.create!(
        provider: "google", uid: "other-uid", email: "actor@example.com", verified_at: Time.current
      )

      outcome = described_class.new(google_hash(uid: "new-uid"), actor: actor).claim

      expect(outcome.code).to eq(:already_linked)
    end

    it "returns :pending_in_progress with the pending link's email when one is in flight" do
      actor.authentications.create!(
        provider: "google", uid: "other-uid", email: "pending@example.com", verified_at: nil
      )

      outcome = described_class.new(google_hash(uid: "new-uid"), actor: actor).claim

      expect(outcome.code).to eq(:pending_in_progress)
      expect(outcome.email).to eq("pending@example.com")
    end

    it "returns :failed when the provider supplies no email" do
      outcome = described_class.new(google_hash(email: nil), actor: actor).claim

      expect(outcome.code).to eq(:failed)
      expect(actor.authentications.google).to be_empty
    end

    it "returns :linked and auto-verifies when the OAuth email matches the user's (case-insensitively)" do
      outcome = described_class.new(google_hash(email: "ACTOR@example.com"), actor: actor).claim

      expect(outcome.code).to eq(:linked)
      expect(actor.authentications.google.sole.verified_at).to be_present
    end

    it "returns :verification_sent with a pending auth when the OAuth email differs" do
      outcome = nil
      expect {
        outcome = described_class.new(google_hash(email: "other@example.com"), actor: actor).claim
      }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)

      expect(outcome.code).to eq(:verification_sent)
      expect(outcome.email).to eq("other@example.com")
      expect(outcome.auth).to eq(actor.authentications.google.sole)
      expect(outcome.auth.verified_at).to be_nil
    end
  end

  describe "new identity while signed out (signup)" do
    it "returns :signups_closed and creates nothing when the gate is shut" do
      outcome = nil
      expect {
        outcome = described_class.new(google_hash, signups_open: false).claim
      }.not_to change(User, :count)

      expect(outcome.code).to eq(:signups_closed)
    end

    it "returns :signed_in with a new user and auto-verified auth for a verified email" do
      outcome = nil
      expect {
        outcome = described_class.new(google_hash(email_verified: true), signups_open: true).claim
      }.to change(User, :count).by(1)

      expect(outcome.code).to eq(:signed_in)
      expect(outcome.user.email_address).to eq("person@example.com")
      expect(outcome.user.authentications.google.sole.verified_at).to be_present
    end

    it "attaches the identity to an existing user who owns a verified email auth" do
      existing = create(:user, email_address: "person@example.com").tap do |u|
        u.authentications.create!(provider: "email", uid: u.email_address, verified_at: Time.current)
      end

      outcome = nil
      expect {
        outcome = described_class.new(google_hash(email_verified: true), signups_open: true).claim
      }.not_to change(User, :count)

      expect(outcome.code).to eq(:signed_in)
      expect(outcome.user).to eq(existing)
    end

    it "returns :failed (C1 collision) when the email belongs to an account without a verified email auth" do
      create(:user, email_address: "person@example.com").tap do |u|
        u.authentications.create!(provider: "email", uid: u.email_address)
      end

      outcome = nil
      expect {
        outcome = described_class.new(google_hash(email_verified: true), signups_open: true).claim
      }.not_to change(User, :count)

      expect(outcome.code).to eq(:failed)
    end

    describe "explicitly unverified provider email" do
      it "returns :unverified_pending, parks the claims on a pending auth, and spends both session tokens" do
        invitation = create(:invitation, email: "person@example.com")

        outcome = nil
        expect {
          outcome = described_class.new(
            google_hash(email_verified: false),
            signups_open: true,
            invitation_token: invitation.token,
            join_token: "some-join-token"
          ).claim
        }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)

        expect(outcome.code).to eq(:unverified_pending)
        expect(outcome.email).to eq("person@example.com")
        expect(outcome.spent_tokens).to contain_exactly(:invitation, :join)

        auth = User.find_by(email_address: "person@example.com").authentications.sole
        expect(auth.verified_at).to be_nil
        expect(auth.pending_invitation_token).to eq(invitation.token)
        expect(auth.pending_join_link_digest).to eq(WorkspaceJoinLink.digest("some-join-token"))
        expect(invitation.reload).to be_pending
      end

      it "returns :failed when the unverified email already belongs to another account (takeover guard)" do
        create(:user, email_address: "person@example.com")

        outcome = nil
        expect {
          outcome = described_class.new(google_hash(email_verified: false), signups_open: true).claim
        }.not_to change(Authentication, :count)

        expect(outcome.code).to eq(:failed)
      end
    end
  end

  describe "pending claims during verified signup" do
    it "consumes a matching invitation and reports the token spent" do
      invitation = create(:invitation, email: "person@example.com")

      outcome = described_class.new(
        google_hash(email_verified: true), signups_open: true, invitation_token: invitation.token
      ).claim

      expect(outcome.code).to eq(:signed_in)
      expect(invitation.reload).to be_accepted
      expect(outcome.user.workspaces).to include(invitation.invitable)
      expect(outcome.spent_tokens).to include(:invitation)
      expect(outcome.problems).to be_empty
    end

    it "skips a mismatched invitation and surfaces the problem on a successful sign-in" do
      invitation = create(:invitation, email: "someone-else@example.com")

      outcome = described_class.new(
        google_hash(email_verified: true), signups_open: true, invitation_token: invitation.token
      ).claim

      expect(outcome.code).to eq(:signed_in)
      expect(invitation.reload).to be_pending
      expect(outcome.problems).to eq([ :invitation_email_mismatch ])
      expect(outcome.spent_tokens).to include(:invitation)
    end

    it "returns :failed and rolls the link back when the invitation is stale" do
      invitation = create(:invitation, :expired, email: "person@example.com")

      outcome = described_class.new(
        google_hash(email_verified: true), signups_open: true, invitation_token: invitation.token
      ).claim

      expect(outcome.code).to eq(:failed)
      expect(outcome.spent_tokens).to include(:invitation)
      expect(Authentication.find_by(provider: "google", uid: "uid-123")).to be_nil
    end

    it "leaves a still-valid join token parked for a pre-existing user (drive-by guard)" do
      create(:user, email_address: "person@example.com").tap do |u|
        u.authentications.create!(provider: "email", uid: u.email_address, verified_at: Time.current)
      end
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies)
        .and_return(%i[invite open_link])
      workspace = create(:workspace, personal: false, join_policy: "open_link")
      link = create(:workspace_join_link, workspace: workspace, created_by: create(:user))
      Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }

      outcome = described_class.new(
        google_hash(email_verified: true), signups_open: true, join_token: link.plaintext_token
      ).claim

      expect(outcome.code).to eq(:signed_in)
      expect(outcome.user.workspaces).not_to include(workspace)
      expect(outcome.spent_tokens).not_to include(:join)
    end
  end

  describe "error narrowing" do
    it "propagates ArgumentError from an unknown provider instead of masking it as :failed" do
      bogus = OmniAuth::AuthHash.new(
        provider: "bogus",
        uid: "x",
        info: { email: "person@example.com", first_name: "Pat", last_name: "Doe" },
        credentials: { token: "tok", refresh_token: nil, expires_at: nil }
      )

      expect {
        described_class.new(bogus, signups_open: true).claim
      }.to raise_error(ArgumentError)
    end
  end
end

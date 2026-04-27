require "rails_helper"

RSpec.describe "OmniAuth Callbacks", type: :request do
  let(:google_auth_hash) do
    OmniAuth::AuthHash.new(
      provider: "google",
      uid: "123456",
      info: {
        email: "oauth@example.com",
        first_name: "Jane",
        last_name: "Doe"
      },
      credentials: {
        token: "mock_token",
        refresh_token: "mock_refresh",
        expires_at: 1.hour.from_now.to_i
      }
    )
  end

  describe "Google OAuth" do
    before do
      OmniAuth.config.mock_auth[:google_oauth2] = google_auth_hash
    end

    context "new user" do
      it "creates a user and authentication" do
        expect {
          get "/auth/google_oauth2/callback"
        }.to change(User, :count).by(1)
          .and change(Authentication, :count).by(1)
      end

      it "signs in the user" do
        get "/auth/google_oauth2/callback"
        expect(response).to redirect_to(root_path)
      end
    end

    context "existing user with matching email and verified email auth" do
      let!(:user) { create(:user, email_address: "oauth@example.com") }

      before do
        user.authentications.create!(provider: "email", uid: "oauth@example.com", verified_at: Time.current)
      end

      it "links the OAuth provider to existing user" do
        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change(User, :count)

        expect(user.authentications.google.count).to eq(1)
      end
    end
  end

  describe "signed-in user linking a new provider" do
    let(:user) { create(:user) }

    before do
      create(:authentication, user: user, provider: "email", uid: user.email_address)
      sign_in(user)
      OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
        provider: "github",
        uid: "789",
        info: { email: user.email_address, first_name: "Jane", last_name: "Doe" },
        credentials: { token: "token", refresh_token: nil, expires_at: nil }
      )
    end

    it "links the provider to the current user" do
      expect {
        get "/auth/github/callback"
      }.to change(user.authentications, :count).by(1)
    end

    it "does not create a new user" do
      expect {
        get "/auth/github/callback"
      }.not_to change(User, :count)
    end

    it "redirects to connected accounts" do
      get "/auth/github/callback"
      expect(response).to redirect_to(account_connected_accounts_path)
    end
  end

  describe "OAuth failure" do
    it "redirects with error" do
      get "/auth/failure", params: { message: "invalid_credentials" }
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "existing OAuth login updates tokens" do
    let!(:user) { create(:user, email_address: "returning@example.com") }
    let!(:auth) do
      user.authentications.create!(
        provider: "google",
        uid: "returning-123",
        oauth_token: "old_token"
      )
    end

    before do
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google",
        uid: "returning-123",
        info: { email: "returning@example.com", first_name: "Return", last_name: "User" },
        credentials: { token: "new_token", refresh_token: "new_refresh", expires_at: 1.hour.from_now.to_i }
      )
    end

    it "updates the OAuth token on re-login" do
      get "/auth/google_oauth2/callback"
      expect(auth.reload.oauth_token).to eq("new_token")
    end
  end

  describe "OAuth does not link to unverified email accounts" do
    let!(:unverified_user) { create(:user, email_address: "unverified@example.com") }

    before do
      # User has email auth but it's not verified
      unverified_user.authentications.create!(provider: "email", uid: "unverified@example.com")
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google",
        uid: "new-oauth-123",
        info: { email: "unverified@example.com", first_name: "Evil", last_name: "User" },
        credentials: { token: "token", refresh_token: nil, expires_at: nil }
      )
    end

    it "does not link the OAuth account to the unverified user" do
      get "/auth/google_oauth2/callback"
      # The unverified user should NOT have a Google authentication linked
      expect(unverified_user.authentications.google.count).to eq(0)
    end
  end

  describe "OAuth with existing unverified account (C1: collision rescue)" do
    let!(:unverified_user) { create(:user, email_address: "existing@example.com") }

    before do
      unverified_user.authentications.create!(provider: "email", uid: "existing@example.com")
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google",
        uid: "collision-123",
        info: { email: "existing@example.com", first_name: "Test", last_name: "User" },
        credentials: { token: "token", refresh_token: nil, expires_at: nil }
      )
    end

    it "redirects with helpful message instead of crashing" do
      get "/auth/google_oauth2/callback"
      expect(response).to redirect_to(new_session_path)
    end

    it "does not create a duplicate user" do
      expect {
        get "/auth/google_oauth2/callback"
      }.not_to change(User, :count)
    end
  end

  describe "OAuth creates user without a password (I1)" do
    before do
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google",
        uid: "passwordless-oauth-123",
        info: { email: "passwordless@example.com", first_name: "No", last_name: "Pass" },
        credentials: { token: "token", refresh_token: nil, expires_at: nil }
      )
    end

    it "creates a passwordless user" do
      get "/auth/google_oauth2/callback"
      user = User.find_by(email_address: "passwordless@example.com")
      expect(user).to be_present
      expect(user.password_digest).to be_nil
    end
  end

  describe "OAuth with missing last_name falls back to 'User' (I3)" do
    before do
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google",
        uid: "no-last-name-456",
        info: { email: "nolastname@example.com", first_name: "Only", last_name: "", name: "" },
        credentials: { token: "token", refresh_token: nil, expires_at: nil }
      )
    end

    it "falls back to 'User' for blank last_name and blank name" do
      get "/auth/google_oauth2/callback"
      user = User.find_by(email_address: "nolastname@example.com")
      expect(user).to be_present
      expect(user.last_name).to eq("User")
    end
  end

  describe "OAuth with missing name fields" do
    before do
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google",
        uid: "no-name-123",
        info: { email: "noname@example.com", first_name: nil, last_name: "Smith", name: "" },
        credentials: { token: "token", refresh_token: nil, expires_at: nil }
      )
    end

    it "falls back to defaults for missing name" do
      get "/auth/google_oauth2/callback"
      user = User.find_by(email_address: "noname@example.com")
      expect(user).to be_present
      expect(user.first_name).to eq("User")
    end
  end

  describe "re-OAuth on existing pending authentication" do
    let(:user) { create(:user, email_address: "bob@example.com") }
    let!(:pending_auth) do
      user.authentications.create!(
        provider: "google", uid: "google-pending",
        email: "bob.work@gmail.com",
        verification_token: "old-token", verification_sent_at: 2.hours.ago,
        verified_at: nil
      )
    end

    before do
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google", uid: "google-pending",
        info: { email: "bob.work@gmail.com" },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
      )
    end
    after { OmniAuth.config.mock_auth.clear; OmniAuth.config.test_mode = false }

    it "regenerates the verification token" do
      old_token = pending_auth.verification_token
      get "/auth/google_oauth2/callback"
      expect(pending_auth.reload.verification_token).not_to eq(old_token)
    end

    it "enqueues a fresh verification email" do
      expect {
        get "/auth/google_oauth2/callback"
      }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
    end

    it "refuses to sign in (does NOT create a session)" do
      get "/auth/google_oauth2/callback"
      expect(response).to redirect_to(new_session_path)
      expect(flash[:notice]).to include("fresh confirmation link")
    end

    context "when the user is signed in as the rightful owner" do
      before { sign_in(user) }

      it "redirects to connected accounts (not new_session_path)" do
        get "/auth/google_oauth2/callback"
        expect(response).to redirect_to(account_connected_accounts_path)
      end

      it "still regenerates the token and sends fresh email" do
        old_token = pending_auth.verification_token
        expect {
          get "/auth/google_oauth2/callback"
        }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
        expect(pending_auth.reload.verification_token).not_to eq(old_token)
      end
    end
  end

  describe "re-OAuth on existing pending authentication when OAuth email has changed" do
    # Documents current behavior: the existing pending row's email is preserved
    # on token regeneration. The new OAuth email from the strategy is ignored.
    # If we ever decide to update email-on-re-OAuth, this test should be
    # updated rather than silently changing behavior.
    let(:user) { create(:user, email_address: "dean@example.com") }
    let!(:dean_pending) do
      user.authentications.create!(
        provider: "google", uid: "dean-google-uid",
        email: "dean.original@gmail.com",
        verification_token: "old-token", verification_sent_at: 1.hour.ago,
        verified_at: nil
      )
    end

    before do
      sign_in(user)
      OmniAuth.config.test_mode = true
      # Same UID, but new email from Google
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google", uid: "dean-google-uid",
        info: { email: "dean.updated@gmail.com" },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
      )
    end
    after { OmniAuth.config.mock_auth.clear; OmniAuth.config.test_mode = false }

    it "preserves the original email on the pending row (does not adopt the new OAuth email)" do
      get "/auth/google_oauth2/callback"
      expect(dean_pending.reload.email).to eq("dean.original@gmail.com")
    end

    it "references the original email in the flash notice" do
      get "/auth/google_oauth2/callback"
      expect(flash[:notice]).to include("dean.original@gmail.com")
    end
  end

  describe "cross-user collision when existing auth is pending (security)" do
    let(:alice) { create(:user, email_address: "alice@example.com") }
    let(:eve) { create(:user, email_address: "eve@example.com") }
    let!(:alices_pending) do
      alice.authentications.create!(
        provider: "google", uid: "alice-google-uid",
        email: "alice.work@gmail.com",
        verification_token: "old-token", verification_sent_at: 1.hour.ago,
        verified_at: nil
      )
    end

    before do
      sign_in(eve)
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google", uid: "alice-google-uid",
        info: { email: "alice.work@gmail.com" },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
      )
    end
    after { OmniAuth.config.mock_auth.clear; OmniAuth.config.test_mode = false }

    it "does NOT regenerate Alice's verification token" do
      old_token = alices_pending.verification_token
      get "/auth/google_oauth2/callback"
      expect(alices_pending.reload.verification_token).to eq(old_token)
    end

    it "does NOT enqueue a verification email to Alice" do
      expect {
        get "/auth/google_oauth2/callback"
      }.not_to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
    end

    it "redirects Eve with a collision alert (not pending_resent)" do
      get "/auth/google_oauth2/callback"
      expect(flash[:alert]).to include("different user")
    end
  end

  describe "cross-user collision" do
    let(:alice) { create(:user, email_address: "alice@example.com") }
    let(:eve)   { create(:user, email_address: "eve@example.com") }

    before do
      alice.authentications.create!(provider: "google", uid: "shared-uid",
        email: "alice@example.com", verified_at: Time.current)
      sign_in(eve)
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google", uid: "shared-uid",
        info: { email: "alice@example.com" },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
      )
    end
    after { OmniAuth.config.mock_auth.clear; OmniAuth.config.test_mode = false }

    it "does not transfer Alice's auth to Eve" do
      expect {
        get "/auth/google_oauth2/callback"
      }.not_to change { alice.authentications.find_by(provider: "google").user_id }
    end

    it "redirects Eve with collision_other_user alert" do
      get "/auth/google_oauth2/callback"
      expect(flash[:alert]).to include("different user")
    end
  end

  describe "Google OAuth with strategy-default provider name (production behavior)" do
    let(:user) { create(:user, email_address: "rachel@example.com") }

    before do
      sign_in(user)
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google_oauth2",  # ← matches what the real strategy emits
        uid: "google-oauth2-prod-1",
        info: { email: "rachel@example.com", name: "Rachel" },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: 1.hour.from_now.to_i }
      )
    end
    after { OmniAuth.config.mock_auth.clear; OmniAuth.config.test_mode = false }

    it "creates the auth with the canonical 'google' provider value" do
      get "/auth/google_oauth2/callback"
      auth = user.authentications.find_by(provider: "google")
      expect(auth).to be_present
      expect(auth.provider).to eq("google")
    end

    it "redirects to connected accounts (auto-verified path: emails match)" do
      get "/auth/google_oauth2/callback"
      expect(response).to redirect_to(account_connected_accounts_path)
      expect(flash[:notice]).to include("linked")
    end
  end

  describe "signed-in user linking (verified flow)" do
    let(:user) { create(:user, email_address: "alice@home.com") }

    before do
      sign_in(user)
      OmniAuth.config.test_mode = true
    end

    after { OmniAuth.config.mock_auth.clear; OmniAuth.config.test_mode = false }

    context "when OAuth email matches user's primary email" do
      before do
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google", uid: "google-1",
          info: { email: "alice@home.com", name: "Alice" },
          credentials: { token: "tok", refresh_token: "rtok", expires_at: 1.hour.from_now.to_i }
        )
      end

      it "creates the auth as verified immediately" do
        get "/auth/google_oauth2/callback"
        auth = user.authentications.find_by(provider: "google")
        expect(auth).to be_verified
        expect(auth.verification_token).to be_nil
      end

      it "redirects to connected accounts with linked notice" do
        get "/auth/google_oauth2/callback"
        expect(response).to redirect_to(account_connected_accounts_path)
        expect(flash[:notice]).to include("linked")
      end
    end

    context "when OAuth email differs from user's primary email" do
      before do
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google", uid: "google-1",
          info: { email: "alice.work@gmail.com", name: "Alice" },
          credentials: { token: "tok", refresh_token: "rtok", expires_at: 1.hour.from_now.to_i }
        )
      end

      it "creates the auth as pending (verified_at nil)" do
        get "/auth/google_oauth2/callback"
        auth = user.authentications.find_by(provider: "google")
        expect(auth.verified_at).to be_nil
        expect(auth.verification_token).to be_present
      end

      it "captures the OAuth email on the auth row" do
        get "/auth/google_oauth2/callback"
        auth = user.authentications.find_by(provider: "google")
        expect(auth.email).to eq("alice.work@gmail.com")
      end

      it "enqueues the verification email" do
        expect {
          get "/auth/google_oauth2/callback"
        }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
      end

      it "redirects to connected accounts with pending banner flash" do
        get "/auth/google_oauth2/callback"
        expect(response).to redirect_to(account_connected_accounts_path)
        expect(flash[:notice]).to include("alice.work@gmail.com")
      end
    end

    context "when user already has an authentication for this provider" do
      before do
        user.authentications.create!(provider: "google", uid: "old-uid",
          email: "alice@home.com", verified_at: Time.current)
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google", uid: "google-different-uid",
          info: { email: "alice@home.com" },
          credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
        )
      end

      it "does not create a second authentication" do
        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change { user.authentications.count }
      end

      it "redirects with already_linked alert" do
        get "/auth/google_oauth2/callback"
        expect(flash[:alert]).to include("already linked")
      end
    end

    context "when OAuth email matches user's primary email with different case" do
      before do
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google", uid: "google-case-1",
          info: { email: "Alice@Home.com", name: "Alice" },
          credentials: { token: "tok", refresh_token: "rtok", expires_at: 1.hour.from_now.to_i }
        )
      end

      it "auto-verifies (case-insensitive comparison)" do
        get "/auth/google_oauth2/callback"
        auth = user.authentications.find_by(provider: "google")
        expect(auth).to be_verified
        expect(auth.verification_token).to be_nil
      end
    end

    context "when OAuth email is missing" do
      before do
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google", uid: "google-noemail-1",
          info: { email: nil, name: "Alice" },
          credentials: { token: "tok", refresh_token: nil, expires_at: nil }
        )
      end

      it "does not create an authentication" do
        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change { Authentication.count }
      end

      it "does not enqueue any mail" do
        expect {
          get "/auth/google_oauth2/callback"
        }.not_to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
      end

      it "redirects with linking_failed alert" do
        get "/auth/google_oauth2/callback"
        expect(flash[:alert]).to include("couldn't link")
      end
    end
  end

  describe "signed-in user re-OAuthing with different OAuth account while pending exists" do
    let(:user) { create(:user, email_address: "carol@home.com") }
    let!(:carols_pending) do
      user.authentications.create!(
        provider: "google", uid: "google-account-A",
        email: "carol.work@gmail.com",
        verification_token: "old-token",
        verification_sent_at: 1.hour.ago,
        verified_at: nil
      )
    end

    before do
      sign_in(user)
      OmniAuth.config.test_mode = true
      # User picks a DIFFERENT Google account this time (different UID)
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google", uid: "google-account-B",
        info: { email: "carol.personal@gmail.com" },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
      )
    end
    after { OmniAuth.config.mock_auth.clear; OmniAuth.config.test_mode = false }

    it "alerts about the pending link with the affected email (not 'already linked')" do
      get "/auth/google_oauth2/callback"
      expect(flash[:alert]).to include("pending")
      expect(flash[:alert]).to include("carol.work@gmail.com")
    end

    it "does not create a new authentication" do
      expect {
        get "/auth/google_oauth2/callback"
      }.not_to change { user.authentications.count }
    end
  end

  describe "production-style AuthHash with strategy-default provider name" do
    # Regression: omniauth-google-oauth2 strategy emits provider: "google_oauth2"
    # in production, but our enum stores "google". The controller must normalize
    # the strategy-name to the enum value before any DB lookup or write.
    let(:user) { create(:user, email_address: "carol@home.com") }

    before do
      sign_in(user)
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google_oauth2",
        uid: "google-prod-1",
        info: { email: "carol@home.com", name: "Carol" },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: 1.hour.from_now.to_i }
      )
    end
    after { OmniAuth.config.mock_auth.clear; OmniAuth.config.test_mode = false }

    it "does not raise and creates a verified google authentication" do
      expect {
        get "/auth/google_oauth2/callback"
      }.to change { user.authentications.where(provider: "google").count }.by(1)
    end

    it "redirects to connected accounts with linked notice (Google, not Google Oauth2)" do
      get "/auth/google_oauth2/callback"
      expect(response).to redirect_to(account_connected_accounts_path)
      expect(flash[:notice]).to include("Google")
      expect(flash[:notice]).not_to include("Google Oauth2")
    end
  end
end

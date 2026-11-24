require "rails_helper"

RSpec.describe "OmniAuth Callbacks", type: :request do
  # Open signup by default; the SIGNUP_MODE gate describe below stubs :invite_only itself.
  before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }

  def sign_in_as(user)
    sign_in(user)
    user
  end

  def google_auth_hash
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

      it "leaves exactly one welcome notification on the new account" do
        get "/auth/google_oauth2/callback"

        registrant = User.find_by(email_address: "oauth@example.com")
        expect(Noticed::Notification.where(recipient: registrant,
                                           type: "WelcomeNotifier::Notification").count).to eq 1
      end
    end

    context "existing user with matching email and verified email auth" do
      it "links the OAuth provider to existing user" do
        user = create(:user, email_address: "oauth@example.com")

        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change(User, :count)

        expect(user.authentications.google.count).to eq(1)
      end

      it "does not welcome a pre-existing user attaching a provider" do
        user = create(:user, email_address: "oauth@example.com")

        get "/auth/google_oauth2/callback"

        expect(Noticed::Notification.where(recipient: user,
                                           type: "WelcomeNotifier::Notification").count).to eq 0
      end
    end
  end

  describe "signed-in user linking a new provider" do
    def signed_in_user_presenting_github
      user = sign_in_as(create(:user, :unverified_email))
      OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
        provider: "github",
        uid: "789",
        info: { email: user.email_address, first_name: "Jane", last_name: "Doe" },
        credentials: { token: "token", refresh_token: nil, expires_at: nil }
      )
      user
    end

    it "links the provider to the current user" do
      user = signed_in_user_presenting_github

      expect {
        get "/auth/github/callback"
      }.to change(user.authentications, :count).by(1)
    end

    it "does not create a new user" do
      signed_in_user_presenting_github

      expect {
        get "/auth/github/callback"
      }.not_to change(User, :count)
    end

    it "redirects to connected accounts" do
      signed_in_user_presenting_github

      get "/auth/github/callback"
      expect(response).to redirect_to(settings_connected_accounts_path)
    end
  end

  # OmniAuth's on_failure lands on /auth/failure; that page is
  # OmniauthFailuresController#show (#1007).
  describe "OAuth failure" do
    it "redirects with error" do
      get "/auth/failure", params: { message: "invalid_credentials" }
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "existing OAuth login updates tokens" do
    before do
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google",
        uid: "returning-123",
        info: { email: "returning@example.com", first_name: "Return", last_name: "User" },
        credentials: { token: "new_token", refresh_token: "new_refresh", expires_at: 1.hour.from_now.to_i }
      )
    end

    it "updates the OAuth token on re-login" do
      user = create(:user, :no_authentications, email_address: "returning@example.com")
      auth = user.authentications.create!(
        provider: "google",
        uid: "returning-123",
        oauth_token: "old_token",
        verified_at: Time.current
      )

      get "/auth/google_oauth2/callback"
      expect(auth.reload.oauth_token).to eq("new_token")
    end
  end

  describe "existing OAuth login for a suspended user" do
    before do
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google",
        uid: "suspended-oauth-123",
        info: { email: "suspended-oauth@example.com", first_name: "Sus", last_name: "Pended" },
        credentials: { token: "token", refresh_token: nil, expires_at: nil }
      )
    end

    it "refuses sign-in with the suspended alert" do
      user = create(:user, :no_authentications, :suspended, email_address: "suspended-oauth@example.com")
      user.authentications.create!(provider: "google", uid: "suspended-oauth-123", verified_at: Time.current)

      get "/auth/google_oauth2/callback"
      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to eq(I18n.t("sessions.create.suspended"))
    end
  end

  # The hold refuses the writes that ride on the sign-in, not only the session (#1129).
  describe "a suspended user presenting a new provider with a parked invitation" do
    it "attaches no provider, accepts no invitation, and shows the suspended alert" do
      create(:user, :suspended, email_address: "held-oauth@example.com")
      invitation = create(:invitation, email: "held-oauth@example.com")
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google",
        uid: "held-oauth-new",
        info: { email: "held-oauth@example.com", first_name: "Held", last_name: "User", email_verified: true },
        credentials: { token: "token", refresh_token: nil, expires_at: nil }
      )
      post accept_invitation_path(token: invitation.token)

      expect { get "/auth/google_oauth2/callback" }
        .not_to change { [ Authentication.count, Membership.count ] }

      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to eq(I18n.t("sessions.create.suspended"))
      expect(invitation.reload).to be_pending
    end
  end

  describe "OAuth does not link to unverified email accounts" do
    before do
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google",
        uid: "new-oauth-123",
        info: { email: "unverified@example.com", first_name: "Evil", last_name: "User" },
        credentials: { token: "token", refresh_token: nil, expires_at: nil }
      )
    end

    it "does not link the OAuth account to the unverified user" do
      unverified_user = create(:user, :unverified_email, email_address: "unverified@example.com")

      get "/auth/google_oauth2/callback"
      expect(unverified_user.authentications.google.count).to eq(0)
    end
  end

  describe "OAuth with existing unverified account (C1: collision rescue)" do
    before do
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google",
        uid: "collision-123",
        info: { email: "existing@example.com", first_name: "Test", last_name: "User" },
        credentials: { token: "token", refresh_token: nil, expires_at: nil }
      )
    end

    it "redirects with helpful message instead of crashing" do
      create(:user, :unverified_email, email_address: "existing@example.com")

      get "/auth/google_oauth2/callback"
      expect(response).to redirect_to(new_session_path)
    end

    it "does not create a duplicate user" do
      create(:user, :unverified_email, email_address: "existing@example.com")

      expect {
        get "/auth/google_oauth2/callback"
      }.not_to change(User, :count)
    end
  end

  describe "OAuth creates user without a password" do
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

  describe "OAuth with missing last_name falls back to 'User'" do
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
    def user_with_pending_google
      user = create(:user, :no_authentications, email_address: "bob@example.com")
      user.authentications.create!(
        provider: "google", uid: "google-pending",
        email: "bob.work@gmail.com",
        verified_at: nil
      )
      user
    end

    before do
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google", uid: "google-pending",
        info: { email: "bob.work@gmail.com" },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
      )
    end

    it "enqueues a fresh verification email" do
      user_with_pending_google

      expect {
        get "/auth/google_oauth2/callback"
      }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
    end

    it "refuses to sign in (does NOT create a session)" do
      user_with_pending_google

      get "/auth/google_oauth2/callback"
      expect(response).to redirect_to(new_session_path)
      expect(flash[:notice]).to eq(I18n.t("omniauth_callbacks.create.pending_resent", email: "bob.work@gmail.com"))
    end

    context "when the user is signed in as the rightful owner" do
      it "redirects to connected accounts (not new_session_path)" do
        sign_in(user_with_pending_google)

        get "/auth/google_oauth2/callback"
        expect(response).to redirect_to(settings_connected_accounts_path)
      end

      it "still sends a fresh verification email" do
        sign_in(user_with_pending_google)

        expect {
          get "/auth/google_oauth2/callback"
        }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
      end
    end
  end

  describe "re-OAuth on existing pending authentication when OAuth email has changed" do
    # Pins current behavior: re-OAuth keeps the pending row's original email and ignores
    # the strategy's new one. Change this test deliberately if that ever changes.
    def signed_in_with_pending_google
      user = create(:user, :no_authentications, email_address: "dean@example.com")
      pending = user.authentications.create!(
        provider: "google", uid: "dean-google-uid",
        email: "dean.original@gmail.com",
        verified_at: nil
      )
      sign_in(user)
      pending
    end

    before do
      OmniAuth.config.test_mode = true
      # Same UID, but new email from Google
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google", uid: "dean-google-uid",
        info: { email: "dean.updated@gmail.com" },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
      )
    end

    it "preserves the original email on the pending row (does not adopt the new OAuth email)" do
      dean_pending = signed_in_with_pending_google

      get "/auth/google_oauth2/callback"
      expect(dean_pending.reload.email).to eq("dean.original@gmail.com")
    end

    it "references the original email in the flash notice" do
      signed_in_with_pending_google

      get "/auth/google_oauth2/callback"
      expect(flash[:notice]).to eq(I18n.t("omniauth_callbacks.create.pending_resent", email: "dean.original@gmail.com"))
    end
  end

  describe "cross-user collision when existing auth is pending (security)" do
    def eve_signed_in_against_alices_pending_google
      alice = create(:user, :no_authentications, email_address: "alice@example.com")
      alice.authentications.create!(
        provider: "google", uid: "alice-google-uid",
        email: "alice.work@gmail.com",
        verified_at: nil
      )
      sign_in(create(:user, :no_authentications, email_address: "eve@example.com"))
    end

    before do
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google", uid: "alice-google-uid",
        info: { email: "alice.work@gmail.com" },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
      )
    end

    it "does NOT enqueue a verification email to Alice" do
      eve_signed_in_against_alices_pending_google

      expect {
        get "/auth/google_oauth2/callback"
      }.not_to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
    end

    it "redirects Eve with a collision alert (not pending_resent)" do
      eve_signed_in_against_alices_pending_google

      get "/auth/google_oauth2/callback"
      expect(flash[:alert]).to eq(I18n.t("omniauth_callbacks.create.collision_other_user", provider: "Google"))
    end
  end

  # Alice holds the verified "shared-uid" Google link; Eve signs in and presents it.
  def alice_linked_while_eve_signs_in(**alice_attrs)
    alice = create(:user, :no_authentications, email_address: "alice@example.com", **alice_attrs)
    alice.authentications.create!(provider: "google", uid: "shared-uid",
      email: "alice@example.com", verified_at: Time.current)
    sign_in(create(:user, :no_authentications, email_address: "eve@example.com"))
    alice
  end

  describe "cross-user collision" do
    before do
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google", uid: "shared-uid",
        info: { email: "alice@example.com" },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
      )
    end

    it "does not transfer Alice's auth to Eve" do
      alice = alice_linked_while_eve_signs_in

      expect {
        get "/auth/google_oauth2/callback"
      }.not_to change { alice.authentications.find_by(provider: "google").user_id }
    end

    it "redirects Eve with collision_other_user alert" do
      alice_linked_while_eve_signs_in

      get "/auth/google_oauth2/callback"
      expect(flash[:alert]).to eq(I18n.t("omniauth_callbacks.create.collision_other_user", provider: "Google"))
    end
  end

  describe "cross-user collision sends defense-in-depth alert to legitimate owner" do
    # Use a real cache store so EmailRecipientThrottle's throttle logic exercises;
    # otherwise null_store makes increment return nil and we can't observe drops.
    around do |ex|
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      ex.run
    ensure
      Rails.cache = original
    end

    before do
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google", uid: "shared-uid",
        info: { email: "alice@example.com" },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
      )
    end

    it "enqueues a collision_alert email to the legitimate owner" do
      alice = alice_linked_while_eve_signs_in(first_name: "Alice")

      expect {
        get "/auth/google_oauth2/callback"
      }.to have_enqueued_mail(AuthenticationMailer, :collision_alert).with(alice, "Google")
    end

    it "drops further alerts to the same recipient once the per-recipient cap is hit" do
      alice_linked_while_eve_signs_in(first_name: "Alice")

      EmailRecipientThrottle::CAP.times { get "/auth/google_oauth2/callback" }

      expect {
        get "/auth/google_oauth2/callback"
      }.not_to have_enqueued_mail(AuthenticationMailer, :collision_alert)
    end
  end

  describe "Google OAuth with strategy-default provider name (production behavior)" do
    before do
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google_oauth2",  # ← matches what the real strategy emits
        uid: "google-oauth2-prod-1",
        info: { email: "rachel@example.com", name: "Rachel" },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: 1.hour.from_now.to_i }
      )
    end

    it "creates the auth with the canonical 'google' provider value" do
      user = sign_in_as(create(:user, :no_authentications, email_address: "rachel@example.com"))

      get "/auth/google_oauth2/callback"
      auth = user.authentications.find_by(provider: "google")
      expect(auth).to be_present
      expect(auth.provider).to eq("google")
    end

    it "redirects to connected accounts (auto-verified path: emails match)" do
      sign_in(create(:user, :no_authentications, email_address: "rachel@example.com"))

      get "/auth/google_oauth2/callback"
      expect(response).to redirect_to(settings_connected_accounts_path)
      expect(flash[:notice]).to eq(I18n.t("omniauth_callbacks.create.linked", provider: "Google"))
    end
  end

  describe "signed-in user linking (verified flow)" do
    def signed_in_alice
      sign_in_as(create(:user, :no_authentications, email_address: "alice@home.com"))
    end

    before do
      OmniAuth.config.test_mode = true
    end

    context "when OAuth email matches user's primary email" do
      before do
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google", uid: "google-1",
          info: { email: "alice@home.com", name: "Alice" },
          credentials: { token: "tok", refresh_token: "rtok", expires_at: 1.hour.from_now.to_i }
        )
      end

      it "creates the auth as verified immediately" do
        user = signed_in_alice

        get "/auth/google_oauth2/callback"
        auth = user.authentications.find_by(provider: "google")
        expect(auth).to be_verified
      end

      it "redirects to connected accounts with linked notice" do
        signed_in_alice

        get "/auth/google_oauth2/callback"
        expect(response).to redirect_to(settings_connected_accounts_path)
        expect(flash[:notice]).to eq(I18n.t("omniauth_callbacks.create.linked", provider: "Google"))
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
        user = signed_in_alice

        get "/auth/google_oauth2/callback"
        auth = user.authentications.find_by(provider: "google")
        expect(auth.verified_at).to be_nil
      end

      it "captures the OAuth email on the auth row" do
        user = signed_in_alice

        get "/auth/google_oauth2/callback"
        auth = user.authentications.find_by(provider: "google")
        expect(auth.email).to eq("alice.work@gmail.com")
      end

      it "enqueues the verification email" do
        signed_in_alice

        expect {
          get "/auth/google_oauth2/callback"
        }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
      end

      it "redirects to connected accounts with pending banner flash" do
        signed_in_alice

        get "/auth/google_oauth2/callback"
        expect(response).to redirect_to(settings_connected_accounts_path)
        expect(flash[:notice]).to eq(I18n.t("omniauth_callbacks.create.pending", email: "alice.work@gmail.com", provider: "Google"))
      end
    end

    context "when user already has an authentication for this provider" do
      def signed_in_alice_with_google
        user = signed_in_alice
        user.authentications.create!(provider: "google", uid: "old-uid",
          email: "alice@home.com", verified_at: Time.current)
        user
      end

      before do
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google", uid: "google-different-uid",
          info: { email: "alice@home.com" },
          credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
        )
      end

      it "does not create a second authentication" do
        user = signed_in_alice_with_google

        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change { user.authentications.count }
      end

      it "redirects with already_linked alert" do
        signed_in_alice_with_google

        get "/auth/google_oauth2/callback"
        expect(flash[:alert]).to eq(I18n.t("omniauth_callbacks.create.already_linked", provider: "Google"))
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
        user = signed_in_alice

        get "/auth/google_oauth2/callback"
        auth = user.authentications.find_by(provider: "google")
        expect(auth).to be_verified
      end
    end

    context "when OAuth email matches user's primary email in a different Unicode form (NFC vs NFD)" do
      # Stored email is NFC, the strategy's is NFD: visually identical, byte-different, so a
      # plain `.downcase ==` would force every OAuth sign-in through unknown-email verification.
      def nfd_email
        "café@example.com".unicode_normalize(:nfd)
      end

      before do
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google", uid: "google-unicode-1",
          info: { email: nfd_email, name: "Café User" },
          credentials: { token: "tok", refresh_token: "rtok", expires_at: 1.hour.from_now.to_i }
        )
      end

      it "auto-verifies (NFC-normalized comparison via EmailNormalizer)" do
        user = sign_in_as(create(:user, :no_authentications, email_address: "café@example.com"))
        expect(nfd_email.bytesize).not_to eq(user.email_address.bytesize)

        get "/auth/google_oauth2/callback"

        auth = user.authentications.find_by(provider: "google")
        expect(auth).to be_verified
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
        signed_in_alice

        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change { Authentication.count }
      end

      it "does not enqueue any mail" do
        signed_in_alice

        expect {
          get "/auth/google_oauth2/callback"
        }.not_to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
      end

      it "redirects with linking_failed alert" do
        signed_in_alice

        get "/auth/google_oauth2/callback"
        expect(flash[:alert]).to include("couldn't link")
      end
    end
  end

  describe "signed-in user re-OAuthing with different OAuth account while pending exists" do
    def signed_in_carol_with_pending_google
      user = create(:user, :no_authentications, email_address: "carol@home.com")
      user.authentications.create!(
        provider: "google", uid: "google-account-A",
        email: "carol.work@gmail.com",
        verified_at: nil
      )
      sign_in_as(user)
    end

    before do
      OmniAuth.config.test_mode = true
      # User picks a DIFFERENT Google account this time (different UID)
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google", uid: "google-account-B",
        info: { email: "carol.personal@gmail.com" },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
      )
    end

    it "alerts about the pending link with the affected email (not 'already linked')" do
      signed_in_carol_with_pending_google

      get "/auth/google_oauth2/callback"
      expect(flash[:alert]).to eq(I18n.t("omniauth_callbacks.create.pending_in_progress", provider: "Google", email: "carol.work@gmail.com"))
    end

    it "does not create a new authentication" do
      user = signed_in_carol_with_pending_google

      expect {
        get "/auth/google_oauth2/callback"
      }.not_to change { user.authentications.count }
    end
  end

  describe "production-style AuthHash with strategy-default provider name" do
    # Regression: the strategy emits provider "google_oauth2" but the enum stores "google";
    # the controller normalizes before any DB lookup or write.
    before do
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google_oauth2",
        uid: "google-prod-1",
        info: { email: "carol@home.com", name: "Carol" },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: 1.hour.from_now.to_i }
      )
    end

    it "does not raise and creates a verified google authentication" do
      user = sign_in_as(create(:user, :no_authentications, email_address: "carol@home.com"))

      expect {
        get "/auth/google_oauth2/callback"
      }.to change { user.authentications.where(provider: "google").count }.by(1)
    end

    it "redirects to connected accounts with linked notice (Google, not Google Oauth2)" do
      sign_in(create(:user, :no_authentications, email_address: "carol@home.com"))

      get "/auth/google_oauth2/callback"
      expect(response).to redirect_to(settings_connected_accounts_path)
      expect(flash[:notice]).to eq(I18n.t("omniauth_callbacks.create.linked", provider: "Google"))
    end
  end

  describe "OAuth provider explicitly reports email as unverified (info.email_verified: false)" do
    # Distrusting email_verified: false blocks takeover via an unverified Google account
    # created with a victim's address.
    context "signed-in user linking, OAuth email matches primary email" do
      def signed_in_linker
        sign_in_as(create(:user, :no_authentications, email_address: "linker@example.com"))
      end

      before do
        OmniAuth.config.test_mode = true
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google", uid: "linker-google-uid",
          info: { email: "linker@example.com", email_verified: false },
          credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
        )
      end

      it "does NOT auto-verify the new authentication (creates as pending)" do
        user = signed_in_linker

        expect {
          get "/auth/google_oauth2/callback"
        }.to change { user.authentications.where(provider: "google").count }.by(1)

        auth = user.authentications.find_by(provider: "google")
        expect(auth.verified_at).to be_nil
      end

      it "sends a verification email" do
        signed_in_linker

        expect {
          get "/auth/google_oauth2/callback"
        }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
      end

      it "redirects to connected accounts with the pending notice (not the linked notice)" do
        signed_in_linker

        get "/auth/google_oauth2/callback"
        expect(response).to redirect_to(settings_connected_accounts_path)
        expect(flash[:notice]).to eq(I18n.t("omniauth_callbacks.create.pending", email: "linker@example.com", provider: "Google"))
      end
    end

    context "new user signup with no existing user matching the email" do
      before do
        OmniAuth.config.test_mode = true
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google", uid: "newbie-google-uid",
          info: { email: "newbie@example.com", first_name: "New", last_name: "Bie", email_verified: false },
          credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
        )
      end

      it "creates the user but with a pending (not auto-verified) authentication" do
        expect {
          get "/auth/google_oauth2/callback"
        }.to change(User, :count).by(1)
          .and change(Authentication, :count).by(1)

        auth = Authentication.find_by(provider: "google", uid: "newbie-google-uid")
        expect(auth.verified_at).to be_nil
      end

      it "sends a verification email" do
        expect {
          get "/auth/google_oauth2/callback"
        }.to have_enqueued_mail(AuthenticationMailer, :link_verification_email)
      end

      it "does NOT sign the user in (redirects to sign-in, not root)" do
        get "/auth/google_oauth2/callback"
        expect(response).to redirect_to(new_session_path)
        expect(flash[:notice]).to eq(I18n.t("omniauth_callbacks.create.unverified_email_pending", email: "newbie@example.com"))
      end
    end

    context "new user signup matching an existing user's email (account takeover risk)" do
      before do
        OmniAuth.config.test_mode = true
        # Attacker controls an unverified Google account using victim's email.
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google", uid: "attacker-google-uid",
          info: { email: "victim@example.com", email_verified: false },
          credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
        )
      end

      it "does NOT link the new Google authentication to the victim's account" do
        victim = create(:user, email_address: "victim@example.com")

        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change { victim.authentications.count }
      end

      it "does NOT create any authentication" do
        create(:user, email_address: "victim@example.com")

        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change(Authentication, :count)
      end

      it "does NOT create a new user (User uniqueness on email_address blocks the create)" do
        create(:user, email_address: "victim@example.com")

        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change(User, :count)
      end

      it "redirects to sign-in with a generic linking-failed alert (does not leak that the email exists)" do
        create(:user, email_address: "victim@example.com")

        get "/auth/google_oauth2/callback"
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to include(I18n.t("omniauth_callbacks.create.linking_failed"))
      end
    end
  end

  describe "OAuth provider explicitly reports email as verified (info.email_verified: true) — regression" do
    # Sanity: when the provider explicitly affirms verification, behavior is
    # unchanged from the pre-gate path (auto-verify, sign in).
    before do
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google", uid: "verified-google-uid",
        info: { email: "verified@example.com", first_name: "Veri", last_name: "Fied", email_verified: true },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: nil }
      )
    end

    it "creates the user with an auto-verified authentication and signs them in" do
      expect {
        get "/auth/google_oauth2/callback"
      }.to change(User, :count).by(1)

      auth = Authentication.find_by(provider: "google", uid: "verified-google-uid")
      expect(auth.verified_at).to be_present
      expect(response).to redirect_to(root_path)
    end
  end

  describe "SIGNUP_MODE gate behavior" do
    def park_invitation(workspace, email)
      invitation = create(:invitation, invitable: workspace, email: email)
      post accept_invitation_path(token: invitation.token)
      invitation
    end

    before do
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google",
        uid: "gate-test-uid",
        info: { email: "newuser@example.com", first_name: "New", last_name: "User", email_verified: true },
        credentials: { token: "tok", refresh_token: "rtok", expires_at: 1.hour.from_now.to_i }
      )
    end


    context "when SIGNUP_MODE is :invite_only with no token (Branch 3, new Google user, allowlist armed)" do
      # MiClassrooms Phase 0 Task 7: OAuth providers listed in
      # OmniauthCallbacksController::SSO_SIGNUP_BYPASS_PROVIDERS (google +
      # okta — each has its own institutional gate: the ALLOWED_GOOGLE_DOMAINS
      # allowlist and Okta org membership respectively) bypass SIGNUP_MODE.
      # This describe block used to assert the opposite (added in Task 10),
      # but that gate never served SSO auto-provisioning well: under the
      # fork's real default (SIGNUP_MODE=invite_only), it blocked every OAuth
      # signup exactly like email self-signup.
      #
      # C1 (final-review fix): the bypass is further conditioned on google's
      # own gate actually being ARMED (a non-empty allowlist) —
      # OmniauthCallbacksController#sso_signup_bypass?. This example stubs the
      # allowlist to match the auth_hash's domain so it continues to pin "the
      # bypass fires when the institutional gate is armed"; the unarmed
      # (empty-allowlist) case — where this must fall back to signups_open?
      # instead — is pinned in spec/requests/omniauth_google_domains_spec.rb,
      # which exercises both the SIGNUP_MODE=invite_only rejection and the
      # SIGNUP_MODE=open pass-through against the unstubbed allowlist default.
      # Email self-signup (RegistrationsController,
      # MagicLinkCallbacksController) is unaffected and stays gated by
      # SIGNUP_MODE — as do providers outside the bypass list (GitHub, next
      # context).
      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
        allow(Rails.configuration.x.auth).to receive(:allowed_google_domains).and_return(%w[example.com])
      end

      it "creates the User and Authentication and signs in despite the closed signup gate" do
        expect {
          get "/auth/google_oauth2/callback"
        }.to change(User, :count).by(1).and change(Authentication, :count).by(1)

        expect(Authentication.find_by(uid: "gate-test-uid")).to be_present
        expect(response).to redirect_to(root_path)
      end
    end

    context "when SIGNUP_MODE is :invite_only and a NEW user arrives via GitHub (Branch 3, NOT bypassed)" do
      # GitHub is NOT in SSO_SIGNUP_BYPASS_PROVIDERS: it has no institutional
      # gate of its own, and its callback route stays live (with
      # allow_unauthenticated_access) even when its button is hidden under
      # sso_only — so letting it bypass SIGNUP_MODE would reopen public
      # self-signup to anyone with any GitHub account. It goes through
      # signups_open? exactly as before Task 7, fail-closed for any provider
      # outside the bypass list.
      let(:github_hash) do
        OmniAuth::AuthHash.new(
          provider: "github",
          uid: "github-gate-uid",
          info: { email: "githubber@example.com", first_name: "Git", last_name: "Hubber" },
          credentials: { token: "tok", refresh_token: nil, expires_at: nil }
        )
      end

      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
        OmniAuth.config.mock_auth[:github] = github_hash
      end

      it "redirects with 303 and creates no User, Authentication, or Session" do
        expect {
          get "/auth/github/callback"
        }.not_to change(User, :count)

        expect(Authentication.find_by(uid: "github-gate-uid")).to be_nil
        expect(Session.count).to eq(0)
        expect(response).to redirect_to(new_session_path)
        expect(response).to have_http_status(:see_other)
        expect(flash[:alert]).to include(I18n.t("registrations.closed.oauth_blocked"))
      end

      it "still allows GitHub signup with a valid invitation token (unchanged template semantics)" do
        invitation = create(:invitation, email: "githubber@example.com")
        post accept_invitation_path(token: invitation.token)

        expect {
          get "/auth/github/callback"
        }.to change(User, :count).by(1)
      end
    end

    context "when SIGNUP_MODE is :open and a NEW user arrives via GitHub (template semantics preserved)" do
      let(:github_hash) do
        OmniAuth::AuthHash.new(
          provider: "github",
          uid: "github-open-uid",
          info: { email: "opengithubber@example.com", first_name: "Open", last_name: "Hubber" },
          credentials: { token: "tok", refresh_token: nil, expires_at: nil }
        )
      end

      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open)
        OmniAuth.config.mock_auth[:github] = github_hash
      end

      it "creates the user and signs them in" do
        expect {
          get "/auth/github/callback"
        }.to change(User, :count).by(1).and change(Authentication, :count).by(1)

        expect(response).to redirect_to(root_path)
      end
    end

    context "when SIGNUP_MODE is :invite_only with a valid invitation token in session (Branch 3, allowed)" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only) }

      it "creates a new user via OAuth and signs in" do
        invitation = create(:invitation, email: "newuser@example.com")
        post accept_invitation_path(token: invitation.token)

        expect {
          get "/auth/google_oauth2/callback"
        }.to change(User, :count).by(1)
      end
    end

    # === CRITICAL REGRESSION: Branch 1 (existing identity) must NOT be blocked ===
    describe "Invited new-user OAuth signup (verified email)" do
      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google",
          uid: "999888",
          info: { email: "newoauth@example.com", first_name: "New", last_name: "OAuth", email_verified: true },
          credentials: { token: "tk", refresh_token: "rt", expires_at: 1.hour.from_now.to_i }
        )
      end

      it "creates the user, accepts the invitation, and adds workspace membership" do
        workspace = create(:workspace)
        invitation = park_invitation(workspace, "newoauth@example.com")

        expect {
          get "/auth/google_oauth2/callback"
        }.to change(User, :count).by(1)

        new_user = User.find_by(email_address: "newoauth@example.com")
        expect(new_user).to be_present
        expect(invitation.reload).to be_accepted
        expect(new_user.workspaces).to include(workspace)
      end

      it "signs the user in" do
        park_invitation(create(:workspace), "newoauth@example.com")

        get "/auth/google_oauth2/callback"
        expect(response).to redirect_to(root_path)
      end
    end

    describe "Invited new-user OAuth signup (UNverified email)" do
      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
        OmniAuth.config.test_mode = true
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google",
          uid: "777666",
          info: { email: "unverified@example.com", first_name: "Pending", last_name: "Verify", email_verified: false },
          credentials: { token: "tk2", refresh_token: "rt2", expires_at: 1.hour.from_now.to_i }
        )
      end

      after { OmniAuth.config.mock_auth[:google_oauth2] = nil }

      it "creates the user and a pending Authentication" do
        park_invitation(create(:workspace), "unverified@example.com")

        expect {
          get "/auth/google_oauth2/callback"
        }.to change(User, :count).by(1).and change(Authentication, :count).by(1)
      end

      it "persists the invitation token on the pending Authentication" do
        invitation = park_invitation(create(:workspace), "unverified@example.com")

        get "/auth/google_oauth2/callback"
        new_user = User.find_by(email_address: "unverified@example.com")
        auth = new_user.authentications.last
        expect(auth.pending_invitation_token).to eq(invitation.token)
        expect(auth.verified_at).to be_nil
      end

      it "does NOT consume the invitation yet (deferred to verification)" do
        invitation = park_invitation(create(:workspace), "unverified@example.com")

        get "/auth/google_oauth2/callback"
        expect(invitation.reload).to be_pending
        expect(invitation.reload.accepted_at).to be_nil
      end

      it "clears the session token after persisting onto the Authentication" do
        park_invitation(create(:workspace), "unverified@example.com")

        get "/auth/google_oauth2/callback"
        expect(session[:pending_invitation_token]).to be_nil
      end

      it "does NOT sign the user in (verification still required)" do
        park_invitation(create(:workspace), "unverified@example.com")

        get "/auth/google_oauth2/callback"
        expect(response).to redirect_to(new_session_path)
      end
    end

    context "when SIGNUP_MODE is :invite_only and an existing user signs in via OAuth (Branch 1)" do
      it "signs in the existing user without creating a new one" do
        user = create(:user, :no_authentications)
        user.authentications.create!(provider: "google", uid: "existing-gate-uid", verified_at: Time.current)
        OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
          provider: "google",
          uid: "existing-gate-uid",
          info: { email: user.email_address },
          credentials: { token: "tok", refresh_token: nil, expires_at: nil }
        )
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)

        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change(User, :count)

        expect(response).to have_http_status(:redirect)
      end
    end
  end

  describe "verified-email OAuth signup with a pending open-link join token" do
    def park_join_token
      # default_self_join_role calls Role.find_by!(slug: "member") — ensure it exists.
      Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
      join_workspace = create(:workspace, join_policy: :open_link)
      join_link = create(:workspace_join_link, workspace: join_workspace)
      post workspace_join_path(workspace_slug: join_workspace.slug, token: join_link.plaintext_token)
      join_link
    end

    before do
      # Permit :open_link at both the instance level (SignupPolicy) and the
      # workspace level (validates join_policy_must_be_permitted_by_instance).
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies)
        .and_return([ :invite, :open_link ])
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open)

      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
        provider: "google",
        uid: "join-oauth-uid-123",
        info: {
          email: "joinoauth@example.com",
          first_name: "Join",
          last_name: "OAuth",
          email_verified: true
        },
        credentials: {
          token: "join_tok",
          refresh_token: "join_rtok",
          expires_at: 1.hour.from_now.to_i
        }
      )
    end

    # #689: OauthLink once enumerated the admission outcomes by hand, so a new
    # one would 500 the callback instead of becoming a :failed outcome.
    context "when #admit raises an admission outcome this code predates" do
      before do
        stub_const("Workspace::FifthOutcome", Class.new(Workspace::AdmissionError))
        allow_any_instance_of(Workspace).to receive(:admit).and_raise(Workspace::FifthOutcome)
      end

      it "reports a failed link rather than erroring out" do
        join_workspace = park_join_token.workspace

        get "/auth/google_oauth2/callback"

        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to eq(I18n.t("omniauth_callbacks.create.linking_failed"))
        expect(Membership.joins(:user).where(workspace: join_workspace,
                                             users: { email_address: "joinoauth@example.com" })).not_to exist
      end
    end

    it "creates the user, auto-verifies the authentication, and admits them as a member" do
      join_workspace = park_join_token.workspace

      expect {
        get "/auth/google_oauth2/callback"
      }.to change(User, :count).by(1)

      new_user = User.find_by(email_address: "joinoauth@example.com")
      expect(new_user).to be_present
      expect(new_user.memberships.kept.where(workspace: join_workspace)).to exist
    end

    context "when the verified email belongs to a PRE-EXISTING user (drive-by join, FU-1)" do
      it "signs them in but does NOT force-join them; the token stays parked for re-consent" do
        join_link = park_join_token
        join_workspace = join_link.workspace
        existing_user = create(:user, email_address: "joinoauth@example.com")

        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change(User, :count)

        expect(existing_user.memberships.kept.where(workspace: join_workspace)).not_to exist
        # Token survives login (SESSION_KEYS_SURVIVING_LOGIN) so the pending-join
        # banner can offer an explicit Join/Dismiss.
        expect(session[:pending_join_token]).to eq(join_link.plaintext_token)
      end
    end
  end
end

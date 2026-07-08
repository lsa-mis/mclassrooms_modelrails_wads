require "rails_helper"

RSpec.describe "Google OAuth domain allowlist", type: :request do
  # MiClassrooms Phase 0 Task 7: Google sign-in is restricted to University of
  # Michigan email domains in production (ALLOWED_GOOGLE_DOMAINS). Okta is
  # NOT subject to this allowlist — org membership is Okta's own gate (see
  # config/initializers/omniauth.rb) — so every example here targets the
  # google_oauth2 strategy only.
  def google_auth_hash(email, uid: "google-uid-#{email}")
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: email, first_name: "Test", last_name: "User", email_verified: true },
      credentials: { token: "tok", refresh_token: "rtok", expires_at: 1.hour.from_now.to_i }
    )
  end

  describe "when the allowlist is configured" do
    before do
      allow(Rails.configuration.x.auth).to receive(:allowed_google_domains)
        .and_return(%w[umich.edu lsa.umich.edu])
    end

    context "with a disallowed domain (gmail.com)" do
      before { OmniAuth.config.mock_auth[:google_oauth2] = google_auth_hash("someone@gmail.com") }

      it "creates no User" do
        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change(User, :count)
      end

      it "creates no Authentication" do
        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change(Authentication, :count)
      end

      it "starts no Session" do
        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change(Session, :count)
      end

      it "redirects to sign-in with an I18n alert" do
        get "/auth/google_oauth2/callback"
        expect(response).to redirect_to(new_session_path)
        expect(flash[:alert]).to eq(I18n.t("omniauth_callbacks.create.google_domain_not_allowed"))
      end
    end

    context "with an allowed domain (umich.edu)" do
      before { OmniAuth.config.mock_auth[:google_oauth2] = google_auth_hash("wolverine@umich.edu") }

      it "creates a User and Authentication and signs in" do
        expect {
          get "/auth/google_oauth2/callback"
        }.to change(User, :count).by(1).and change(Authentication, :count).by(1)

        expect(response).to redirect_to(root_path)
      end
    end

    context "with an allowed secondary domain (lsa.umich.edu)" do
      before { OmniAuth.config.mock_auth[:google_oauth2] = google_auth_hash("wolverine@lsa.umich.edu") }

      it "creates a User" do
        expect {
          get "/auth/google_oauth2/callback"
        }.to change(User, :count).by(1)
      end
    end

    context "with mixed-case domain (Someone@UMICH.EDU)" do
      before { OmniAuth.config.mock_auth[:google_oauth2] = google_auth_hash("Someone@UMICH.EDU") }

      it "matches case-insensitively and succeeds" do
        expect {
          get "/auth/google_oauth2/callback"
        }.to change(User, :count).by(1)
      end
    end

    context "with a lookalike domain that is a superstring prefix (evilumich.edu)" do
      before { OmniAuth.config.mock_auth[:google_oauth2] = google_auth_hash("user@evilumich.edu") }

      it "is rejected (no end_with? tricks — exact match only)" do
        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change(User, :count)

        expect(response).to redirect_to(new_session_path)
      end
    end

    context "with a lookalike domain that appends a suffix (umich.edu.evil.com)" do
      before { OmniAuth.config.mock_auth[:google_oauth2] = google_auth_hash("user@umich.edu.evil.com") }

      it "is rejected (no start_with?/include? tricks — exact match only)" do
        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change(User, :count)

        expect(response).to redirect_to(new_session_path)
      end
    end
  end

  describe "allowlist entry normalization (EmailNormalizer parity)" do
    # Entries are normalized at read time (AuthConfig.allowed_google_domains:
    # NFC + strip + downcase + punycode via EmailNormalizer.punycode_domain) —
    # the same canonical form EmailNormalizer.normalize produces for the
    # OAuth email's domain part — so a sloppily-formatted env value can't
    # silently lock everyone out.
    context "with a trailing-whitespace allowlist entry" do
      before do
        allow(Rails.configuration.x.auth).to receive(:allowed_google_domains)
          .and_return([ " umich.edu " ])
        OmniAuth.config.mock_auth[:google_oauth2] = google_auth_hash("someone@umich.edu")
      end

      it "still matches" do
        expect {
          get "/auth/google_oauth2/callback"
        }.to change(User, :count).by(1)
      end
    end

    context "with a mixed-case allowlist entry" do
      before do
        allow(Rails.configuration.x.auth).to receive(:allowed_google_domains)
          .and_return([ "UMICH.edu" ])
        OmniAuth.config.mock_auth[:google_oauth2] = google_auth_hash("someone@umich.edu")
      end

      it "still matches" do
        expect {
          get "/auth/google_oauth2/callback"
        }.to change(User, :count).by(1)
      end
    end
  end

  describe "when the allowlist is empty/unset (dev-friendly default)" do
    before do
      allow(Rails.configuration.x.auth).to receive(:allowed_google_domains).and_return([])
    end

    # An empty allowlist means the domain CHECK is disabled (every domain
    # passes google_domain_allowed?) — but, per C1 below, it separately means
    # the SIGNUP_MODE bypass is NOT granted. Stub signup mode open here so
    # this example isolates the domain-check behavior; the SIGNUP_MODE
    # interaction gets its own describe block right below.
    context "with SIGNUP_MODE open" do
      before do
        allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open)
        OmniAuth.config.mock_auth[:google_oauth2] = google_auth_hash("anyone@example.com")
      end

      it "allows any domain through and still provisions the new user" do
        expect {
          get "/auth/google_oauth2/callback"
        }.to change(User, :count).by(1)

        expect(response).to redirect_to(root_path)
      end
    end

    # C1 (final-review fix): the SIGNUP_MODE bypass in
    # OmniauthCallbacksController::SSO_SIGNUP_BYPASS_PROVIDERS used to apply
    # to google unconditionally. That was fail-open: with the allowlist
    # empty/unset (the gate unarmed), ANY Google account could self-provision
    # even while the instance is invite_only/SSO-only. #sso_signup_bypass?
    # now requires AuthConfig.allowed_google_domains.any? before treating
    # google as gated, so an unarmed allowlist falls through to the normal
    # signups_open? check — exactly like github (see the describe block
    # below this one) — instead of bypassing it.
    context "with SIGNUP_MODE invite_only (the real default)" do
      before do
        OmniAuth.config.mock_auth[:google_oauth2] = google_auth_hash("newperson@example.com", uid: "new-person-uid")
      end

      it "does not stub signup mode — the real default is :invite_only" do
        expect(Rails.configuration.x.signup.mode).to eq(:invite_only)
      end

      it "rejects the new Google user: creates no User, Authentication, or Session" do
        expect {
          get "/auth/google_oauth2/callback"
        }.not_to change(User, :count)

        expect(Authentication.find_by(uid: "new-person-uid")).to be_nil
        expect(Session.count).to eq(0)
      end

      it "redirects with the closed-signup alert (303, not the domain-not-allowed alert)" do
        get "/auth/google_oauth2/callback"

        expect(response).to redirect_to(new_session_path)
        expect(response).to have_http_status(:see_other)
        expect(flash[:alert]).to include(I18n.t("registrations.closed.oauth_blocked"))
      end

      context "an EXISTING Google user (Branch 1 — the bypass gap only affects NEW-user provisioning)" do
        let!(:user) { create(:user, email_address: "returner@example.com") }
        let!(:authentication) do
          user.authentications.create!(provider: "google", uid: "returning-uid", verified_at: Time.current)
        end

        before do
          OmniAuth.config.mock_auth[:google_oauth2] =
            google_auth_hash("returner@example.com", uid: "returning-uid")
        end

        it "still signs in without creating a new user" do
          expect {
            get "/auth/google_oauth2/callback"
          }.not_to change(User, :count)

          expect(response).to redirect_to(root_path)
        end
      end
    end
  end

  describe "SSO provisioning bypasses closed email self-signup (Task 7)" do
    # Task 6's Okta spec appeared to provision new users successfully under
    # SIGNUP_MODE=invite_only, but that was a test-mode artifact: its
    # top-level `before` stubbed Rails.configuration.x.signup.mode to :open.
    # Under the REAL default (SIGNUP_MODE=invite_only, unstubbed here),
    # OAuth-provisioned accounts must still succeed — the domain allowlist
    # (Google) / org membership (Okta) is the intended gate for SSO, not
    # SIGNUP_MODE. Email self-signup (magic link / registrations) stays
    # closed under the same default — see
    # spec/requests/magic_link_callbacks_spec.rb's invite-only coverage.
    before do
      allow(Rails.configuration.x.auth).to receive(:allowed_google_domains).and_return(%w[umich.edu])
      OmniAuth.config.mock_auth[:google_oauth2] = google_auth_hash("newwolverine@umich.edu")
    end

    it "does not stub signup mode — the real default is :invite_only" do
      expect(Rails.configuration.x.signup.mode).to eq(:invite_only)
    end

    it "provisions the new user via Google OAuth anyway" do
      expect {
        get "/auth/google_oauth2/callback"
      }.to change(User, :count).by(1).and change(Authentication, :count).by(1)

      expect(response).to redirect_to(root_path)
    end

    # The bypass is scoped to providers with their own institutional gate
    # (google: domain allowlist; okta: org membership) —
    # OmniauthCallbacksController::SSO_SIGNUP_BYPASS_PROVIDERS. GitHub has no
    # such gate: its strategy stays configured and its callback route stays
    # live even though the button is hidden under sso_only, so letting it
    # bypass SIGNUP_MODE would reopen public self-signup to anyone with any
    # GitHub account. It must go through signups_open? exactly as before
    # Task 7 — fail-closed for any provider not in the bypass list.
    context "a NEW user arriving via GitHub (no institutional gate)" do
      before do
        OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
          provider: "github",
          uid: "github-new-user-uid",
          info: { email: "stranger@example.com", first_name: "Any", last_name: "Body" },
          credentials: { token: "tok", refresh_token: nil, expires_at: nil }
        )
      end

      it "is rejected under the real invite_only default: nothing created, closed-signup alert" do
        expect {
          get "/auth/github/callback"
        }.not_to change(User, :count)

        expect(Authentication.find_by(uid: "github-new-user-uid")).to be_nil
        expect(Session.count).to eq(0)
        expect(response).to redirect_to(new_session_path)
        expect(response).to have_http_status(:see_other)
        expect(flash[:alert]).to include(I18n.t("registrations.closed.oauth_blocked"))
      end
    end
  end
end

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
end

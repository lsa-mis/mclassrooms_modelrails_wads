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

    context "existing user with matching email" do
      let!(:user) { create(:user, email_address: "oauth@example.com") }

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
end

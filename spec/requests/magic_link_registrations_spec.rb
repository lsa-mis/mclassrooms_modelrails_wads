require "rails_helper"

RSpec.describe "Magic Link Registrations", type: :request do
  describe "GET /magic_link_registration/:token" do
    it "shows the name-only registration form" do
      token = MagicLinkToken.create_for_email("newuser@example.com")
      get magic_link_registration_path(token: token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("magic_link_registrations.new.title"))
    end

    it "rejects expired tokens" do
      token = MagicLinkToken.create_for_email("newuser@example.com")
      MagicLinkToken.find_by(token: token).update!(expires_at: 1.hour.ago)
      get magic_link_registration_path(token: token)
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "POST /magic_link_registration/:token" do
    it "creates an account and signs in" do
      token = MagicLinkToken.create_for_email("newuser@example.com")
      expect {
        post magic_link_registration_path(token: token), params: {
          user: { first_name: "New", last_name: "User" }
        }
      }.to change(User, :count).by(1)

      user = User.find_by(email_address: "newuser@example.com")
      expect(user.first_name).to eq("New")
      expect(response).to redirect_to(root_path)
    end

    it "creates a passwordless account" do
      token = MagicLinkToken.create_for_email("newuser@example.com")
      post magic_link_registration_path(token: token), params: {
        user: { first_name: "New", last_name: "User" }
      }
      user = User.find_by(email_address: "newuser@example.com")
      expect(user.password_digest).to be_nil
    end
  end
end

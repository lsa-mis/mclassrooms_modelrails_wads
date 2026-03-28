require "rails_helper"

RSpec.describe "Account Profiles", type: :request do
  let(:user) { create(:user) }
  before { sign_in(user) }

  describe "GET /account/profile/edit" do
    it "renders the edit form" do
      get edit_account_profile_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /account/profile" do
    it "updates the user's name" do
      patch account_profile_path, params: {
        user: { first_name: "Updated", last_name: "Name" }
      }
      expect(user.reload.first_name).to eq("Updated")
      expect(response).to redirect_to(edit_account_profile_path)
    end

    it "updates the user's email" do
      patch account_profile_path, params: {
        user: { email_address: "newemail@example.com" }
      }
      expect(user.reload.email_address).to eq("newemail@example.com")
    end
  end

  describe "PATCH /account/profile with invalid params" do
    it "returns unprocessable entity for blank first_name" do
      patch account_profile_path, params: { user: { first_name: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end

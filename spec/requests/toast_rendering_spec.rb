require "rails_helper"

RSpec.describe "Toast rendering", type: :request do
  describe "success flash" do
    let(:user) { create(:user) }

    it "renders a pill in the toast-pills container" do
      post session_path, params: {
        email_address: user.email_address,
        password: "SecureP@ssw0rd123!"
      }
      follow_redirect!
      expect(response.body).to include('id="toast-pills"')
      expect(response.body).to include('data-controller="toast-pill"')
      expect(response.body).to include('role="status"')
    end
  end
end

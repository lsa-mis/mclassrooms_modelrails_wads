require "rails_helper"

# Post-sign-in landing is workspace-agnostic and fork-overridable. The template
# default routes an authenticated user with no saved return_to to their home
# (authenticated_home_path => root_path). A fork overrides ONE method to land
# users at /me. (organizer-onboarding design, Template BLOCKERS.)
RSpec.describe "Authenticated landing seam", type: :request do
  let(:user) { create(:user) }

  describe "default destination after sign-in" do
    it "lands on root when there is no saved return_to" do
      post session_path, params: { email_address: user.email_address, password: "SecureP@ssw0rd123!" }
      expect(response).to redirect_to(root_url)
    end

    it "still honors a saved return_to over the home default" do
      get edit_settings_profile_path
      expect(response).to redirect_to(new_session_path)
      post session_path, params: { email_address: user.email_address, password: "SecureP@ssw0rd123!" }
      expect(response).to redirect_to(edit_settings_profile_url)
    end
  end

  describe "the seam is overridable" do
    it "after_authentication_url derives from authenticated_home_path" do
      controller = SessionsController.new
      controller.set_request!(ActionDispatch::TestRequest.create)
      allow(controller).to receive(:session).and_return({})

      expect(controller.send(:authenticated_home_path)).to eq(Rails.application.routes.url_helpers.root_path)
      expect(controller.send(:after_authentication_url)).to eq(Rails.application.routes.url_helpers.root_path)

      allow(controller).to receive(:authenticated_home_path).and_return(Rails.application.routes.url_helpers.about_path)
      expect(controller.send(:after_authentication_url)).to eq(Rails.application.routes.url_helpers.about_path)
    end
  end
end

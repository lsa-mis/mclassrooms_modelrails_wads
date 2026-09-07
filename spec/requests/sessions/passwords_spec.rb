require "rails_helper"

# The password step of signing in is the new of a password resource nested
# under the session; the form still posts to sessions#create. Was
# SessionsController#password_form at GET /session/password (#1007).
RSpec.describe "Session Passwords", type: :request do
  describe "GET /session/password/new" do
    let(:user) { create(:user) }

    it "renders the password form for the looked-up address without signing in" do
      get new_session_password_path(email_address: user.email_address)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("sessions.passwords.new.password_label"))
      expect(response.body).to include(CGI.escapeHTML(user.email_address))
      expect(response.body).to include(session_path) # the form's action
    end

    it "offers the magic link instead" do
      get new_session_password_path(email_address: user.email_address)
      expect(response.body).to include(I18n.t("sessions.passwords.new.use_magic_link"))
    end
  end
end

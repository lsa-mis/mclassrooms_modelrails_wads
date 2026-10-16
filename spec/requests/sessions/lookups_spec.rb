require "rails_helper"

# The email-first step of signing in: POST /session/lookup creates an email
# lookup, which sends the right magic link and renders the next step inline.
# Was SessionsController#lookup (#1007); the path helper is unchanged.
RSpec.describe "Session Lookups", type: :request do
  describe "POST /session/lookup (passwordless-first)" do
    it "sends a magic link to a password user instead of going straight to the password form" do
      user = create(:user) # has a password
      expect {
        post session_lookup_path, params: { email_address: user.email_address }
      }.to change { MagicLinkToken.where(email: user.email_address).count }.by(1)
      expect(response.body).to include(I18n.t("sessions.check_email.title"))
      expect(response.body).to include(I18n.t("sessions.check_email.use_password")) # secondary link present
    end

    it "sends nothing to a new email when signups are closed, and says what it says to a known one" do
      allow_any_instance_of(Sessions::LookupsController).to receive(:signups_open?).and_return(false)
      expect {
        post session_lookup_path, params: { email_address: "newcomer@example.com" }
      }.not_to change(MagicLinkToken, :count)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("sessions.check_email.title"))
    end
  end

  describe "POST /session/lookup (smart routing)" do
    context "user with password" do
      let(:user) { create(:user) }

      it "returns check_email with secondary password link (passwordless-first)" do
        post session_lookup_path, params: { email_address: user.email_address }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("sessions.check_email.title"))
        expect(response.body).to include(I18n.t("sessions.check_email.use_password"))
      end

      it "offers the password form inline, so the address never travels in a URL" do
        post session_lookup_path, params: { email_address: user.email_address }
        page = Capybara.string(response.body)
        expect(page).to have_css("details form[action='#{session_path}']", visible: :all)
        expect(response.body).not_to include("email_address=")
      end
    end

    context "user without password" do
      let(:user) { create(:user) }

      before { user.update_column(:password_digest, nil) }

      it "offers the password form all the same, so the page says nothing about who holds one" do
        post session_lookup_path, params: { email_address: user.email_address }
        expect(response.body).to include(I18n.t("sessions.check_email.use_password"))
      end

      it "shows check email confirmation inline" do
        post session_lookup_path, params: { email_address: user.email_address }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("sessions.check_email.title"))
        expect(response.body).to include(user.email_address)
        expect(response.body).to include(I18n.t("sessions.check_email.expiry"))
        expect(response.body).to include('role="status"')
      end
    end

    context "non-existent email" do
      it "shows check email when signups are open (no information leakage)" do
        allow_any_instance_of(Sessions::LookupsController).to receive(:signups_open?).and_return(true)
        post session_lookup_path, params: { email_address: "ghost@example.com" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("sessions.check_email.title"))
        expect(response.body).to include("ghost@example.com")
        expect(response.body).to include(I18n.t("sessions.check_email.use_password"))
      end

      it "shows the same check email page inside the frame when signups are closed" do
        allow_any_instance_of(Sessions::LookupsController).to receive(:signups_open?).and_return(false)
        post session_lookup_path, params: { email_address: "ghost@example.com" }
        expect(response).to have_http_status(:ok)
        frame = Capybara.string(response.body).find("turbo-frame#sign_in_form", visible: :all)
        expect(frame).to have_text(I18n.t("sessions.check_email.title"))
      end
    end

    context "invalid email format" do
      it "rejects email without a domain TLD" do
        post session_lookup_path, params: { email_address: "hd@humbledaisy" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("sessions.lookups.create.invalid_email"))
      end

      it "rejects email without any structure" do
        post session_lookup_path, params: { email_address: "notanemail" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("sessions.lookups.create.invalid_email"))
      end

      it "re-renders a form that posts the address under the name the controller reads" do
        post session_lookup_path, params: { email_address: "notanemail" }
        field = Capybara.string(response.body).find("turbo-frame#sign_in_form input[type='email']")
        expect(field[:name]).to eq("email_address")
      end

      it "accepts the corrected address from that re-rendered form" do
        post session_lookup_path, params: { email_address: "notanemail" }
        name = Capybara.string(response.body).find("input[type='email']")[:name]
        post session_lookup_path, params: { name => "someone@example.com" }
        expect(response.body).to include(I18n.t("sessions.check_email.title"))
      end

      it "rejects blank email" do
        post session_lookup_path, params: { email_address: "" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("sessions.lookups.create.invalid_email"))
      end
    end
  end
end

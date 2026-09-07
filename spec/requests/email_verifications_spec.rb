require "rails_helper"

RSpec.describe "Email verifications", type: :request do
  describe "GET /email_verification/new" do
    let(:user) { create(:user, :unverified_email) }

    it "renders the check-your-email screen for a signed-in user" do
      sign_in(user)
      get new_email_verification_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(user.email_address)
    end

    it "requires authentication" do
      get new_email_verification_path
      expect(response).to redirect_to(new_session_path)
    end

    it "styles the resend and continue actions with real button utilities (phantom classes fixed)" do
      sign_in(user)
      get new_email_verification_path

      html = Capybara.string(response.body)
      expect(html).to have_css("button.btn-secondary[type='submit']") # resend button_to renders <button> in this app
      expect(html).to have_css("a.btn-primary", text: I18n.t("email_verifications.new.continue"))
      expect(html).to have_no_css(".btn-neutral")
      expect(html).to have_no_css("a.btn-solid")
    end
  end

  describe "POST /email_verification_resend" do
    let(:user) { create(:user, :unverified_email) }

    it "re-enqueues the verification email and returns to the check screen" do
      sign_in(user)
      expect {
        post email_verification_resend_path
      }.to have_enqueued_mail(AuthenticationMailer, :verification_email)
      expect(response).to redirect_to(new_email_verification_path)
    end
  end

  let(:user) { create(:user, :unverified_email) }
  let(:authentication) { user.authentications.email.sole }

  describe "GET /email_verification?token=" do
    it "renders the confirmation and verifies nothing" do
      get email_verification_path(token: authentication.generate_token_for(:email_verification))

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("email_verifications.show.title"))
      expect(authentication.reload).not_to be_verified
    end

    it "redirects with the invalid flash for a bad token" do
      get email_verification_path(token: "invalid")
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("email_verifications.show.invalid_or_expired"))
    end
  end

  describe "POST /email_verification" do
    it "verifies and continues to after-authentication" do
      post email_verification_path, params: { token: authentication.generate_token_for(:email_verification) }

      expect(authentication.reload).to be_verified
      expect(response).to redirect_to(root_path) # after_authentication_url with no return_to and no client-only user
      expect(flash[:notice]).to eq(I18n.t("email_verifications.create.success"))
    end

    it "rejects an expired token" do
      token = authentication.generate_token_for(:email_verification)
      travel(Authentication::TOKEN_LIFETIME + 1.minute) do
        post email_verification_path, params: { token: token }
      end
      expect(authentication.reload.verified_at).to be_nil
    end

    it "refuses a spent token" do
      token = authentication.generate_token_for(:email_verification)
      authentication.verify!

      post email_verification_path, params: { token: token }
      expect(flash[:alert]).to eq(I18n.t("email_verifications.show.invalid_or_expired"))
    end

    it "rejects an invalid token" do
      post email_verification_path, params: { token: "invalid" }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to be_present
    end
  end
end

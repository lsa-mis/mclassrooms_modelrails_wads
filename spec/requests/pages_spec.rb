require "rails_helper"

RSpec.describe "Pages", type: :request do
  describe "GET /" do
    it "returns the home page" do
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.home.hero.title"))
    end

    it "includes the footer" do
      get root_path
      expect(response.body).to include(I18n.t("footer.about"))
    end

    it "includes navigation" do
      get root_path
      expect(response.body).to include(I18n.t("application.name"))
    end
  end

  describe "sign-up CTA visibility" do
    context "when SIGNUP_MODE is :open" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }

      it "shows the Sign up CTA button on the landing page" do
        get root_path
        # The bottom-CTA button ("Create your account") is only rendered when signups_open?.
        expect(response.body).to include(I18n.t("pages.home.cta.button"))
      end
    end

    context "when SIGNUP_MODE is :invite_only without a token" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only) }

      it "does NOT show the Sign up CTA button on the landing page" do
        get root_path
        # The CTA button ("Create your account") is suppressed when signups are closed.
        expect(response.body).not_to include(I18n.t("pages.home.cta.button"))
      end

      it "still shows the Sign in CTA" do
        get root_path
        expect(response.body).to include(new_session_path)
      end
    end
  end

  describe "GET /about" do
    it "returns the about page with mission" do
      get about_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.about.hero.title"))
    end
  end

  describe "GET /privacy" do
    it "returns the privacy page with policy sections" do
      get privacy_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.privacy.title"))
    end
  end

  describe "GET /contact" do
    it "returns the contact page with methods" do
      get contact_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.contact.hero.title"))
    end
  end
end

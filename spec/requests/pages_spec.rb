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

  describe "sign-in CTA visibility" do
    # The landing-page CTAs are sign-IN, which is unconditional in this app —
    # only sign-UP is gated by signups_open? (see app/views/pages/home.html.erb).
    # They must never vanish based on signup posture, so both modes assert the
    # same thing here.
    context "when SIGNUP_MODE is :open" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }

      it "shows the Sign in CTA button on the landing page" do
        get root_path
        expect(response.body).to include(I18n.t("pages.home.cta.button"))
        expect(response.body).to include(new_session_path)
      end
    end

    context "when SIGNUP_MODE is :invite_only without a token" do
      before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only) }

      it "still shows the Sign in CTA" do
        get root_path
        expect(response.body).to include(I18n.t("pages.home.cta.button"))
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

  # Fix wave (task-8 review): the shared announcements/_banner partial is
  # wired at this call site via @announcement = Announcement.for(:about_page)
  # (PagesController#about) — proves the render actually reaches the page
  # (would fail if that call site were removed or the slot name typo'd),
  # mirroring the home_page banner proof in
  # spec/requests/admin/announcements_spec.rb.
  describe "the about_page banner" do
    it "renders the about_page announcement's body when present" do
      create(:announcement, slot: "about_page", body: "About page notice")

      get about_path

      expect(response.body).to include("About page notice")
      expect(response.body).to include(I18n.t("announcements.banner.aria_label"))
    end

    it "renders nothing when no about_page announcement exists" do
      get about_path

      expect(response.body).not_to include(I18n.t("announcements.banner.aria_label"))
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

require "rails_helper"

# One pages resource, show keyed by name; the templates are the allowlist (#1007).
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

      it "renders the secondary hero CTA as a brand-outline button" do
        get root_path
        expect(Capybara.string(response.body)).to have_css("a.btn-outline-primary",
          text: I18n.t("pages.home.hero.cta_secondary"))
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

  describe "landing page for a signed-in user" do
    let(:user) { create(:user) }

    before do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open)
      sign_in(user)
    end

    # Fork behavior (differs from the template's workspaces-link version):
    # a signed-in visitor's CTAs point at the product — Find a Room — and the
    # bottom CTA keeps its shared title, swapping only subtitle + button
    # (pages.home.cta.*_signed_in keys; see app/views/pages/home.html.erb).
    it "swaps the hero CTA for a Find-a-Room link" do
      get root_path
      expect(Capybara.string(response.body)).to have_link(
        I18n.t("pages.home.hero.cta_primary_signed_in"), href: find_a_room_path
      )
    end

    it "softens the bottom CTA section and links to Find a Room" do
      get root_path
      page = Capybara.string(response.body)
      expect(response.body).to include(I18n.t("pages.home.cta.title"))
      expect(response.body).to include(I18n.t("pages.home.cta.subtitle_signed_in"))
      expect(page).to have_link(I18n.t("pages.home.cta.button_signed_in"), href: find_a_room_path)
    end

    it "does not render a sign-in link CTA" do
      get root_path
      expect(Capybara.string(response.body)).to have_no_link(
        I18n.t("pages.home.hero.cta_primary"), href: new_session_path
      )
    end

    it "shows the Find-a-Room CTA even when signups are closed" do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:invite_only)
      get root_path
      expect(Capybara.string(response.body)).to have_link(
        I18n.t("pages.home.cta.button_signed_in"), href: find_a_room_path
      )
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

    # Guards the :long format on the "last updated" stamp — switching the
    # template to :short, or dropping the `l` call for a raw strftime, fails
    # here. It does NOT guard locale overrides: a fork redefining
    # date.formats.long moves the rendered output and an `I18n.l` expectation
    # together, so the literal is the only version that can fail.
    # Time is frozen because Date.current would otherwise be evaluated once in
    # the request and once in the assertion — different values across midnight.
    it "renders the updated-on date in the :long format" do
      travel_to Time.zone.local(2026, 7, 25, 12, 0, 0) do
        get privacy_path
        expect(response.body).to include("July 25, 2026")
      end
    end
  end

  describe "GET /contact" do
    it "returns the contact page with methods" do
      get contact_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pages.contact.hero.title"))
    end
  end

  describe "GET /:id for a name that is not a page" do
    it "is not routable, so the constraint is the first fence" do
      get "/pricing"
      expect(response).to have_http_status(:not_found)
    end
  end
end

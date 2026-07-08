require "rails_helper"

RSpec.describe "Static pages", type: :system do
  describe "layout" do
    it "has a skip-to-content link" do
      visit root_path
      expect(page).to have_css("a[href='#main-content']", visible: :all)
    end

    it "has a main content landmark" do
      visit root_path
      expect(page).to have_css("main#main-content")
    end

    it "has a lang attribute on html" do
      visit root_path
      expect(page).to have_css("html[lang='en']")
    end

    it "has the theme controller on the html element" do
      visit root_path
      expect(page).to have_css("html[data-controller~='theme']")
    end

    it "has a header with navigation" do
      visit root_path
      expect(page).to have_css("header nav")
    end

    it "displays the site logo SVG in the header" do
      visit root_path
      within("header nav") do
        expect(page).to have_css("svg[aria-hidden='true']")
      end
    end

    it "has a footer" do
      visit root_path
      expect(page).to have_css("footer")
    end

    it "footer contains site links" do
      visit root_path
      within("footer") do
        expect(page).to have_link(I18n.t("footer.about"))
        expect(page).to have_link(I18n.t("footer.privacy"))
        expect(page).to have_link(I18n.t("footer.contact"))
      end
    end

    it "displays the site logo in the footer" do
      visit root_path
      within("footer") do
        expect(page).to have_css("svg[aria-hidden='true']")
        expect(page).to have_text(I18n.t("application.name"))
      end
    end

    it "navigation contains the app name as home link" do
      visit root_path
      within("header nav") do
        expect(page).to have_link(I18n.t("application.name"), href: root_path)
      end
    end

    it "has a theme toggle button" do
      visit root_path
      within("header nav") do
        expect(page).to have_css("button[aria-label]", text: /Light|Dark|System/i, visible: :all)
      end
    end

    it "has a mobile menu toggle button" do
      visit root_path
      expect(page).to have_button(I18n.t("navigation.mobile_menu.open"), visible: :all)
    end

    it "has toast containers for pills and cards" do
      visit root_path
      expect(page).to have_css("#toast-pills[aria-label]", visible: :all)
      expect(page).to have_css("#toast-cards[aria-label]", visible: :all)
    end
  end

  describe "toast notifications" do
    let(:user) { create(:user) }

    def sign_in_via_form
      visit new_session_path
      fill_in I18n.t("sessions.new.email_label"), with: user.email_address
      click_button I18n.t("sessions.new.continue")
      expect(page).to have_text(I18n.t("sessions.check_email.title"))
      token = MagicLinkToken.where(email: user.email_address).order(:created_at).last.token
      visit magic_link_callback_path(token: token)
      expect(page).to have_text(I18n.t("magic_link_callbacks.show.signed_in"))
    end

    it "shows a pill toast with progress bar on successful sign-in" do
      sign_in_via_form
      expect(page).to have_css("[data-controller='toast-pill']")
      expect(page).to have_css("[data-toast-pill-target='progress']")
    end

    it "preserves theme preference across fresh page loads via cookie" do
      visit root_path
      # Cycle to dark: system → light → dark
      find("[data-controller='theme-toggle']").click
      find("[data-controller='theme-toggle']").click
      expect(page).to have_css("html.dark")

      # Full page load (not Turbo) — cookie should restore dark mode
      visit root_path
      expect(page).to have_css("html[data-theme-theme-value='dark']")
    end
  end

  describe "home page" do
    before { visit root_path }

    it "displays the hero title" do
      expect(page).to have_text(I18n.t("pages.home.hero.title"))
    end

    it "displays the hero subtitle" do
      expect(page).to have_text(I18n.t("pages.home.hero.subtitle"))
    end

    it "has call-to-action buttons when signups are open" do
      allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open)
      visit root_path
      expect(page).to have_link(I18n.t("pages.home.hero.cta_primary"))
      expect(page).to have_link(I18n.t("pages.home.hero.cta_secondary"))
    end

    it "displays feature cards" do
      expect(page).to have_text(I18n.t("pages.home.features.capacity.title"))
      expect(page).to have_text(I18n.t("pages.home.features.media.title"))
      expect(page).to have_text(I18n.t("pages.home.features.alerts.title"))
    end
  end

  describe "about page" do
    before { visit about_path }

    it "displays the page title" do
      expect(page).to have_text(I18n.t("pages.about.hero.title"))
    end

    it "displays the mission" do
      expect(page).to have_text(I18n.t("pages.about.mission.title"))
    end

    it "lists key features" do
      expect(page).to have_text(I18n.t("pages.about.features.title"))
    end
  end

  describe "privacy page" do
    before { visit privacy_path }

    it "displays the page title" do
      expect(page).to have_text(I18n.t("pages.privacy.title"))
    end

    it "has policy sections" do
      expect(page).to have_text(I18n.t("pages.privacy.collection.title"))
      expect(page).to have_text(I18n.t("pages.privacy.usage.title"))
      expect(page).to have_text(I18n.t("pages.privacy.security.title"))
    end
  end

  describe "contact page" do
    before { visit contact_path }

    it "displays the page title" do
      expect(page).to have_text(I18n.t("pages.contact.hero.title"))
    end

    it "displays contact methods" do
      expect(page).to have_text(I18n.t("pages.contact.methods.title"))
    end
  end

  %w[about privacy contact].each do |page_name|
    describe "#{page_name} page" do
      it "renders with 200 status" do
        visit send(:"#{page_name}_path")
        expect(page).to have_text(I18n.t("pages.#{page_name}.title", default: I18n.t("pages.#{page_name}.hero.title", default: page_name.titleize)))
      end
    end
  end

  describe "accessibility (axe-core)" do
    # Audits at WCAG 2.2 AAA — the project standard. `axe_clean_in_both_themes?`
    # toggles to light, runs axe; toggles to dark, runs axe; ANDs the result.
    let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

    %w[home about privacy contact].each do |page_name|
      it "#{page_name} page passes automated accessibility checks (light + dark)" do
        path = page_name == "home" ? root_path : send(:"#{page_name}_path")
        visit path
        expect(axe_clean_in_both_themes?(axe_options)).to be(true),
          "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
      end
    end

    it "sign-in page passes automated accessibility checks (light + dark)" do
      visit new_session_path
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end

    # sessions/new is the single entry point for both sign-in and sign-up
    # (passwordless-first posture). The sign-in accessibility test above already
    # covers this page; this example is retained as a named anchor for the
    # sign-up entry path now that registration/new is removed.
    it "sign-up entry page (sessions/new) passes automated accessibility checks (light + dark)" do
      visit new_session_path
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end
end

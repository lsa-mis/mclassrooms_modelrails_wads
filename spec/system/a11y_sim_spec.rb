require "rails_helper"

RSpec.describe "Accessibility simulation drop-up", type: :system do
  def dismiss_cookie_banner
    page.execute_script(<<~JS)
      document.querySelectorAll('[data-controller="biscuit"]').forEach(el => el.remove());
    JS
  end

  describe "outside development" do
    it "does not render the trigger" do
      visit root_path
      expect(page).not_to have_content(I18n.t("a11y_sim.dev_badge"))
    end
  end

  describe "in development" do
    before { allow(Rails.env).to receive(:development?).and_return(true) }

    it "renders the trigger in the footer with the Normal mode label" do
      visit root_path
      within("footer") do
        expect(page).to have_content(I18n.t("a11y_sim.dev_badge"))
        expect(page).to have_content(I18n.t("a11y_sim.prefix"))
        expect(page).to have_content(I18n.t("a11y_sim.modes.normal"))
      end
    end

    it "opens the menu when the trigger is clicked" do
      visit root_path
      dismiss_cookie_banner
      find("[data-a11y-sim-target='trigger']").click
      expect(page).to have_css("[data-a11y-sim-target='menu']:not(.hidden)")
      I18n.t("a11y_sim.modes").each_value do |label|
        expect(page).to have_content(label)
      end
    end

    it "applies the matching body class when a mode is selected" do
      visit root_path
      dismiss_cookie_banner
      find("[data-a11y-sim-target='trigger']").click
      find("[data-a11y-sim-target='item'][data-mode='blur']").click

      expect(page).to have_css("body.a11y-sim-blur")
      expect(page).not_to have_css("body.a11y-sim-deuteranopia")
    end

    it "closes the menu and clears the body class when returning to Normal" do
      visit root_path
      dismiss_cookie_banner
      find("[data-a11y-sim-target='trigger']").click
      find("[data-a11y-sim-target='item'][data-mode='deuteranopia']").click
      expect(page).to have_css("body.a11y-sim-deuteranopia")

      find("[data-a11y-sim-target='trigger']").click
      find("[data-a11y-sim-target='item'][data-mode='normal']").click
      expect(page).not_to have_css("body.a11y-sim-deuteranopia")
      expect(page).not_to have_css("body[class*='a11y-sim-']")
    end
  end
end

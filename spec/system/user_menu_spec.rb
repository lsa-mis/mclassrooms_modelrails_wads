require "rails_helper"

RSpec.describe "User menu dropdown", type: :system do
  let(:user) { create(:user, first_name: "Jane", last_name: "Doe") }

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: "SecureP@ssw0rd123!"
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_text(I18n.t("sessions.create.success"))
    visit root_path
  end

  # Invoke a keyboard event on the dropdown controller via Playwright.
  # Programmatic KeyboardEvent dispatch does not reach main-world Stimulus
  # listeners in Playwright's isolated context, so we call the handler directly.
  def send_dropdown_key(key)
    page.driver.with_playwright_page do |pw_page|
      pw_page.evaluate(<<~JS)
        (function() {
          var el = document.querySelector('[data-controller~="dropdown"]');
          var c = window.Stimulus.getControllerForElementAndIdentifier(el, 'dropdown');
          if (c) c.handleKeydown(new KeyboardEvent('keydown', { key: '#{key}', bubbles: true }));
        })()
      JS
    end
  end

  before do
    sign_in_via_form(user)
  end

  describe "opening and closing" do
    it "opens on click and shows menu items" do
      find("#user-menu-button").click
      expect(page).to have_css("#user-menu", visible: :visible)
      expect(page).to have_text(user.full_name)
      expect(page).to have_text(user.email_address)
    end

    it "closes on second click" do
      find("#user-menu-button").click
      expect(page).to have_css("#user-menu", visible: :visible)
      find("#user-menu-button").click
      expect(page).to have_no_css("#user-menu", visible: :visible)
    end

    it "closes on Escape key" do
      find("#user-menu-button").click
      expect(page).to have_css("#user-menu", visible: :visible)
      send_dropdown_key("Escape")
      expect(page).to have_no_css("#user-menu", visible: :visible)
    end
  end

  describe "keyboard navigation" do
    before do
      find("#user-menu-button").click
      expect(page).to have_css("#user-menu", visible: :visible)
    end

    it "focuses first menu item on open" do
      focused_text = page.evaluate_script("document.activeElement?.textContent?.trim()")
      expect(focused_text).to eq(I18n.t("navigation.profile"))
    end

    it "ArrowDown moves focus to next item" do
      send_dropdown_key("ArrowDown")
      focused_text = page.evaluate_script("document.activeElement?.textContent?.trim()")
      expect(focused_text).to eq(I18n.t("navigation.notifications"))
    end

    it "ArrowDown wraps from last to first item" do
      send_dropdown_key("ArrowDown")
      send_dropdown_key("ArrowDown")
      send_dropdown_key("ArrowDown")
      focused_text = page.evaluate_script("document.activeElement?.textContent?.trim()")
      expect(focused_text).to eq(I18n.t("navigation.profile"))
    end

    it "ArrowUp wraps from first to last item" do
      send_dropdown_key("ArrowUp")
      focused_text = page.evaluate_script("document.activeElement?.textContent?.trim()")
      expect(focused_text).to eq(I18n.t("navigation.sign_out"))
    end

    it "Home key focuses first item" do
      send_dropdown_key("ArrowDown")
      send_dropdown_key("Home")
      focused_text = page.evaluate_script("document.activeElement?.textContent?.trim()")
      expect(focused_text).to eq(I18n.t("navigation.profile"))
    end

    it "End key focuses last item" do
      send_dropdown_key("End")
      focused_text = page.evaluate_script("document.activeElement?.textContent?.trim()")
      expect(focused_text).to eq(I18n.t("navigation.sign_out"))
    end

    it "returns focus to trigger button on Escape" do
      send_dropdown_key("Escape")
      focused_id = page.evaluate_script("document.activeElement?.id")
      expect(focused_id).to eq("user-menu-button")
    end

    it "Space key activates focused menu item" do
      # First item (Profile link) is focused on open
      send_dropdown_key(" ")
      expect(page).to have_current_path(edit_account_profile_path)
    end

    it "Enter key activates focused menu item" do
      send_dropdown_key("Enter")
      expect(page).to have_current_path(edit_account_profile_path)
    end
  end

  describe "navigation" do
    it "profile link navigates to profile page" do
      find("#user-menu-button").click
      click_link I18n.t("navigation.profile")
      expect(page).to have_current_path(edit_account_profile_path)
    end

    it "sign out ends session" do
      find("#user-menu-button").click
      click_button I18n.t("navigation.sign_out")
      expect(page).to have_current_path(new_session_path)
    end
  end

  describe "unauthenticated" do
    it "shows sign in link instead of avatar" do
      Capybara.reset_sessions!
      visit root_path
      expect(page).to have_link(I18n.t("navigation.sign_in"))
      expect(page).to have_no_css("#user-menu-button", visible: :visible)
    end
  end
end

require "rails_helper"

# D1 simplified the user-menu dropdown to a clickable identity-block row
# (avatar + name + email linking to the personal-context profile) and a
# sign-out button. Notifications + Notification preferences moved out of
# the dropdown (notifications live on the standalone header bell;
# preferences live in the Settings hub sidebar).
#
# Post-D1 addition: an "All workspaces" link (workspaces#index) was added
# between identity and sign-out so signed-in users on non-workspace-scoped
# pages (marketing landing, auth flows) have an in-product path to their
# workspaces list — the only place the sidebar switcher does NOT render.
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

  describe "dropdown contents (identity block + all workspaces + sign out)" do
    before do
      find("#user-menu-button").click
      expect(page).to have_css("#user-menu", visible: :visible)
    end

    it "renders a clickable identity block linking to the personal-context profile" do
      within "#user-menu" do
        expect(page).to have_link(href: edit_account_profile_path)
        # Identity block carries the user's full name + email address
        expect(page).to have_text(user.full_name)
        expect(page).to have_text(user.email_address)
      end
    end

    it "renders an All workspaces link to the workspaces index" do
      within "#user-menu" do
        expect(page).to have_link(I18n.t("navigation.all_workspaces"), href: workspaces_path)
      end
    end

    it "renders a sign-out button" do
      within "#user-menu" do
        expect(page).to have_button(I18n.t("navigation.sign_out"))
      end
    end

    it "does NOT render a separate Profile link (the identity block IS the profile link)" do
      within "#user-menu" do
        # The dropdown still routes to the profile page via the identity
        # block — there should not be a SECOND text link labeled "Profile".
        expect(page).not_to have_link(I18n.t("navigation.profile"))
      end
    end

    it "renders a Notifications link (v2: standalone bell removed; user menu is the canonical triage entry)" do
      within "#user-menu" do
        expect(page).to have_link(I18n.t("navigation.notifications"), href: account_notifications_path)
      end
    end

    it "does NOT render a Notification preferences link (accessible via Settings sidebar)" do
      within "#user-menu" do
        expect(page).not_to have_link(I18n.t("navigation.notification_preferences"))
        expect(page).not_to have_link(href: edit_account_notification_preferences_path)
      end
    end
  end

  describe "keyboard navigation" do
    before do
      find("#user-menu-button").click
      expect(page).to have_css("#user-menu", visible: :visible)
    end

    it "focuses first menu item (identity link) on open" do
      focused_href = page.evaluate_script("document.activeElement?.getAttribute('href')")
      expect(focused_href).to eq(edit_account_profile_path)
    end

    it "ArrowDown moves focus from identity to Notifications (second item, v2)" do
      send_dropdown_key("ArrowDown")
      focused_href = page.evaluate_script("document.activeElement?.getAttribute('href')")
      expect(focused_href).to eq(account_notifications_path)
    end

    it "ArrowDown twice moves focus to All workspaces (third item)" do
      send_dropdown_key("ArrowDown") # identity → Notifications
      send_dropdown_key("ArrowDown") # Notifications → All workspaces
      focused_href = page.evaluate_script("document.activeElement?.getAttribute('href')")
      expect(focused_href).to eq(workspaces_path)
    end

    it "ArrowDown thrice moves focus to sign-out (fourth and final item)" do
      send_dropdown_key("ArrowDown")
      send_dropdown_key("ArrowDown")
      send_dropdown_key("ArrowDown")
      focused_text = page.evaluate_script("document.activeElement?.textContent?.trim()")
      expect(focused_text).to eq(I18n.t("navigation.sign_out"))
    end

    it "ArrowDown wraps from last to first item" do
      send_dropdown_key("ArrowDown") # identity → Notifications
      send_dropdown_key("ArrowDown") # Notifications → All workspaces
      send_dropdown_key("ArrowDown") # All workspaces → sign-out
      send_dropdown_key("ArrowDown") # sign-out → wraps to identity
      focused_href = page.evaluate_script("document.activeElement?.getAttribute('href')")
      expect(focused_href).to eq(edit_account_profile_path)
    end

    it "ArrowUp wraps from first to last item" do
      send_dropdown_key("ArrowUp")
      focused_text = page.evaluate_script("document.activeElement?.textContent?.trim()")
      expect(focused_text).to eq(I18n.t("navigation.sign_out"))
    end

    it "Home key focuses first item" do
      send_dropdown_key("ArrowDown")
      send_dropdown_key("Home")
      focused_href = page.evaluate_script("document.activeElement?.getAttribute('href')")
      expect(focused_href).to eq(edit_account_profile_path)
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

    it "Space key activates focused identity link" do
      send_dropdown_key(" ")
      expect(page).to have_current_path(edit_account_profile_path)
    end

    it "Enter key activates focused identity link" do
      send_dropdown_key("Enter")
      expect(page).to have_current_path(edit_account_profile_path)
    end
  end

  describe "navigation" do
    it "identity-block link navigates to profile page" do
      find("#user-menu-button").click
      within "#user-menu" do
        find("a[href='#{edit_account_profile_path}']").click
      end
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

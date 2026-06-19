require "rails_helper"

RSpec.describe "Registration form validation", type: :system do
  before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }

  describe "error display" do
    it "shows error summary and inline errors on invalid submission" do
      visit new_registration_path
      click_button I18n.t("registrations.new.submit")

      # Error summary should be visible
      expect(page).to have_css("[role='alert']")

      # Inline errors should appear next to fields
      expect(page).to have_css("#user_email_address-error[role='alert']")
      expect(page).to have_css("#user_first_name-error[role='alert']")
    end

    it "shows duplicate email error" do
      create(:user, email_address: "taken@example.com")
      visit new_registration_path

      fill_in I18n.t("registrations.new.email_label"), with: "taken@example.com"
      fill_in I18n.t("registrations.new.first_name_label"), with: "Jane"
      fill_in I18n.t("registrations.new.last_name_label"), with: "Doe"
      fill_in I18n.t("registrations.new.password_label"), with: "SecureP@ssw0rd123!"
      fill_in I18n.t("registrations.new.password_confirmation_label"), with: "SecureP@ssw0rd123!"
      click_button I18n.t("registrations.new.submit")

      expect(page).to have_css("[role='alert']")
      expect(page).to have_text(/already been taken/i)
    end

    it "shows password too short error" do
      visit new_registration_path

      fill_in I18n.t("registrations.new.email_label"), with: "new@example.com"
      fill_in I18n.t("registrations.new.first_name_label"), with: "Jane"
      fill_in I18n.t("registrations.new.last_name_label"), with: "Doe"
      fill_in I18n.t("registrations.new.password_label"), with: "short"
      fill_in I18n.t("registrations.new.password_confirmation_label"), with: "short"
      click_button I18n.t("registrations.new.submit")

      expect(page).to have_css("[role='alert']")
      expect(page).to have_text(/too short/i)
    end

    it "escapes HTML in name fields (XSS prevention)" do
      visit new_registration_path

      fill_in I18n.t("registrations.new.first_name_label"), with: "<script>alert('xss')</script>"
      fill_in I18n.t("registrations.new.last_name_label"), with: "Doe"
      fill_in I18n.t("registrations.new.email_label"), with: "xss@example.com"
      fill_in I18n.t("registrations.new.password_label"), with: "SecureP@ssw0rd123!"
      fill_in I18n.t("registrations.new.password_confirmation_label"), with: "SecureP@ssw0rd123!"
      click_button I18n.t("registrations.new.submit")

      # Wait for navigation away from the form (Capybara auto-waits on this matcher).
      # Without this, the raw-HTML check below could race the in-flight submission
      # and read a stale page.
      expect(page).to have_current_path(new_email_verification_path)

      # XSS contract: the user's payload must appear ESCAPED in the rendered HTML,
      # never as a literal `<script>` element. Check the raw HTML for the exact
      # unescaped form (negative) and the auto-escaped form (positive).
      #
      # This is more reliable than `not_to have_css("script")` — every page emits
      # ~3 layout `<script>` tags (theme_script, importmap, module loader). Those
      # are normally `display: none` via browser UA styles and excluded by Capybara's
      # default visibility filter, but Playwright's during-navigation visibility
      # computation can briefly return inconsistent results, making the element-
      # presence assertion flaky.
      expect(page.html).not_to include("<script>alert('xss')</script>")
      expect(page.html).to include("&lt;script&gt;alert(") # positive: escape ran
    end
  end
end

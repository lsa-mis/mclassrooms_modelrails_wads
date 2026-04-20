require "rails_helper"

RSpec.describe "Magic link registration", type: :system do
  describe "new user via smart lookup" do
    it "sends a registration link and allows account creation" do
      visit new_session_path

      fill_in I18n.t("sessions.new.email_label"), with: "brand-new@example.com"
      click_button I18n.t("sessions.new.continue")

      expect(page).to have_text(I18n.t("sessions.check_email.title"))

      # Extract the registration token from the database
      token_record = MagicLinkToken.find_by(email: "brand-new@example.com")
      visit magic_link_callback_path(token: token_record.token)

      expect(page).to have_text(I18n.t("magic_link_callbacks.new_registration.title"))
      expect(page).to have_text("brand-new@example.com")

      fill_in I18n.t("magic_link_callbacks.new_registration.first_name_label"), with: "Alice"
      fill_in I18n.t("magic_link_callbacks.new_registration.last_name_label"), with: "Wonderland"
      click_button I18n.t("magic_link_callbacks.new_registration.submit")

      expect(page).to have_text(I18n.t("magic_link_callbacks.create.registered"))
      expect(User.find_by(email_address: "brand-new@example.com")).to be_present
    end
  end

  describe "registration with expired token" do
    it "rejects and redirects to sign in" do
      token = MagicLinkToken.create_for_email("expired-reg@example.com")
      MagicLinkToken.find_by(token: token).update!(expires_at: 1.hour.ago)

      visit magic_link_callback_path(token: token)

      expect(page).to have_text(I18n.t("magic_link_callbacks.show.invalid"))
    end
  end

  describe "registration with consumed token" do
    it "rejects and redirects to sign in" do
      token = MagicLinkToken.create_for_email("consumed-reg@example.com")
      MagicLinkToken.find_by(token: token).consume!

      visit magic_link_callback_path(token: token)

      expect(page).to have_text(I18n.t("magic_link_callbacks.show.invalid"))
    end
  end

  describe "registration with missing name" do
    it "prevents submission via browser validation on required fields" do
      token = MagicLinkToken.create_for_email("noname@example.com")

      visit magic_link_callback_path(token: token)

      # Fields are required — browser prevents submission, user stays on form
      click_button I18n.t("magic_link_callbacks.new_registration.submit")

      expect(page).to have_text(I18n.t("magic_link_callbacks.new_registration.title"))
      expect(User.find_by(email_address: "noname@example.com")).to be_nil
    end
  end
end

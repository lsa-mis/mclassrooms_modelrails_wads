require "rails_helper"

RSpec.describe "Magic link registration", type: :system do
  # Pin signup mode to :open for every registration spec. The test boot default is
  # :invite_only, so a stray empty-form POST (a Playwright native-validation race in
  # the missing-name spec) would otherwise hit the create gate and render "invitation only".
  before { allow(Rails.configuration.x.signup).to receive(:mode).and_return(:open) }

  describe "new user via smart lookup" do
    it "sends a registration link and allows account creation" do
      visit new_session_path

      fill_in I18n.t("sessions.new.email_label"), with: "brand-new@example.com"
      click_button I18n.t("sessions.new.continue")

      expect(page).to have_text(I18n.t("sessions.check_email.title"))

      visit magic_link_callback_path(token: MagicLinkToken.create_for_email("brand-new@example.com"))

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
      MagicLinkToken.find_by(token_digest: MagicLinkToken.digest(token)).update!(expires_at: 1.hour.ago)

      visit magic_link_callback_path(token: token)

      expect(page).to have_text(I18n.t("magic_link_callbacks.show.invalid"))
    end
  end

  describe "registration with consumed token" do
    it "rejects and redirects to sign in" do
      token = MagicLinkToken.create_for_email("consumed-reg@example.com")
      MagicLinkToken.find_by(token_digest: MagicLinkToken.digest(token)).consume!

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

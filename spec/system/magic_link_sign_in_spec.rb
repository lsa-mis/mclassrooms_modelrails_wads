require "rails_helper"

RSpec.describe "Magic link sign-in", type: :system do
  describe "existing passwordless user" do
    let(:user) do
      u = create(:user)
      u.update_column(:password_digest, nil)
      u
    end

    it "sends a magic link and signs the user in when they click it" do
      visit new_session_path

      fill_in I18n.t("sessions.new.email_label"), with: user.email_address
      click_button I18n.t("sessions.new.continue")

      expect(page).to have_text(I18n.t("sessions.check_email.title"))
      expect(page).to have_text(user.email_address)

      # Visit the magic link (equivalent to the emailed one) and confirm sign-in.
      token = MagicLinkToken.create_for_email(user.email_address)
      visit magic_link_callback_path(token: token)
      click_button I18n.t("magic_link_callbacks.confirm.sign_in_button")

      expect(page).to have_text(I18n.t("magic_link_callbacks.show.signed_in"))
    end
  end

  describe "existing user with password" do
    let(:user) { create(:user) }

    it "sends a magic link and shows a 'use password instead' link" do
      visit new_session_path

      fill_in I18n.t("sessions.new.email_label"), with: user.email_address
      click_button I18n.t("sessions.new.continue")

      # Magic-link is now the default for ALL users; password-holders also land here
      expect(page).to have_text(I18n.t("sessions.check_email.title"))
      expect(page).to have_text(user.email_address)

      # The 'use password instead' escape hatch is present for password-holders
      expect(page).to have_link(I18n.t("sessions.check_email.use_password"),
                                href: session_password_form_path(email_address: user.email_address))

      # Sign in via the magic link (confirm on the interstitial).
      token = MagicLinkToken.create_for_email(user.email_address)
      visit magic_link_callback_path(token: token)
      click_button I18n.t("magic_link_callbacks.confirm.sign_in_button")

      expect(page).to have_text(I18n.t("magic_link_callbacks.show.signed_in"))
    end
  end

  describe "expired token" do
    let(:user) { create(:user) }
    let(:token) do
      t = MagicLinkToken.create_for_email(user.email_address)
      MagicLinkToken.find_by(token_digest: MagicLinkToken.digest(t)).update!(expires_at: 20.minutes.ago)
      t
    end

    it "rejects the token and shows an error" do
      visit magic_link_callback_path(token: token)

      expect(page).to have_text(I18n.t("magic_link_callbacks.show.invalid"))
    end
  end

  describe "invalid token" do
    it "rejects and shows an error" do
      visit magic_link_callback_path(token: "bogus-token")

      expect(page).to have_text(I18n.t("magic_link_callbacks.show.invalid"))
    end
  end

  describe "confirmation page accessibility (SEC-5)" do
    let(:user) { create(:user) }
    let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

    it "renders the sign-in confirmation accessibly in both themes" do
      token = MagicLinkToken.create_for_email(user.email_address)
      visit magic_link_callback_path(token: token)
      expect(page).to have_button(I18n.t("magic_link_callbacks.confirm.sign_in_button"))
      expect(page).to have_link(I18n.t("magic_link_callbacks.confirm.cancel"))
      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations found:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end

  describe "already-consumed token" do
    let(:user) { create(:user) }

    it "rejects a token that was already used" do
      raw_token = MagicLinkToken.create_for_email(user.email_address)

      visit magic_link_callback_path(token: raw_token)
      click_button I18n.t("magic_link_callbacks.confirm.sign_in_button")
      expect(page).to have_text(I18n.t("magic_link_callbacks.show.signed_in"))

      # Token was consumed on confirm — visiting again should fail
      visit magic_link_callback_path(token: raw_token)
      expect(page).to have_text(I18n.t("magic_link_callbacks.show.invalid"))
    end
  end
end

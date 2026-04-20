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

      # Extract the magic link token and visit it directly
      token_record = MagicLinkToken.where(email: user.email_address).order(:created_at).last
      visit magic_link_callback_path(token: token_record.token)

      expect(page).to have_text(I18n.t("magic_link_callbacks.show.signed_in"))
    end
  end

  describe "existing user with password" do
    let(:user) { create(:user) }

    it "shows password form, then allows switching to magic link" do
      visit new_session_path

      fill_in I18n.t("sessions.new.email_label"), with: user.email_address
      click_button I18n.t("sessions.new.continue")

      expect(page).to have_text(I18n.t("sessions.lookup.password_prompt"))

      click_button I18n.t("sessions.password_form.use_magic_link")

      expect(page).to have_text(I18n.t("magic_links.create.check_email"))

      # Extract the magic link token and visit it directly
      token_record = MagicLinkToken.where(email: user.email_address).order(:created_at).last
      visit magic_link_callback_path(token: token_record.token)

      expect(page).to have_text(I18n.t("magic_link_callbacks.show.signed_in"))
    end
  end

  describe "expired token" do
    let(:user) { create(:user) }
    let(:token) do
      t = MagicLinkToken.create_for_email(user.email_address)
      MagicLinkToken.find_by(token: t).update!(expires_at: 20.minutes.ago)
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

  describe "already-consumed token" do
    let(:user) { create(:user) }

    it "rejects a token that was already used" do
      raw_token = MagicLinkToken.create_for_email(user.email_address)

      visit magic_link_callback_path(token: raw_token)
      expect(page).to have_text(I18n.t("magic_link_callbacks.show.signed_in"))

      # Token was consumed on first visit — visiting again should fail
      visit magic_link_callback_path(token: raw_token)
      expect(page).to have_text(I18n.t("magic_link_callbacks.show.invalid"))
    end
  end
end

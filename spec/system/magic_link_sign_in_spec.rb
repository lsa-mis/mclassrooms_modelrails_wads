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
      user.reload
      visit magic_link_session_path(token: user.magic_link_token)

      expect(page).to have_text(I18n.t("magic_link_sessions.show.success"))
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
      user.reload
      visit magic_link_session_path(token: user.magic_link_token)

      expect(page).to have_text(I18n.t("magic_link_sessions.show.success"))
    end
  end

  describe "expired token" do
    let(:user) do
      u = create(:user)
      u.generate_magic_link_token!
      u.update_column(:magic_link_sent_at, 20.minutes.ago)
      u
    end

    it "rejects the token and shows an error" do
      visit magic_link_session_path(token: user.magic_link_token)

      expect(page).to have_text(I18n.t("magic_link_sessions.show.invalid_or_expired"))
    end
  end

  describe "invalid token" do
    it "rejects and shows an error" do
      visit magic_link_session_path(token: "bogus-token")

      expect(page).to have_text(I18n.t("magic_link_sessions.show.invalid_or_expired"))
    end
  end

  describe "already-consumed token" do
    let(:user) { create(:user) }

    it "rejects a token that was already used" do
      user.generate_magic_link_token!
      token = user.magic_link_token

      visit magic_link_session_path(token: token)
      expect(page).to have_text(I18n.t("magic_link_sessions.show.success"))

      # Sign out and try the same token again
      visit magic_link_session_path(token: token)
      expect(page).to have_text(I18n.t("magic_link_sessions.show.invalid_or_expired"))
    end
  end
end

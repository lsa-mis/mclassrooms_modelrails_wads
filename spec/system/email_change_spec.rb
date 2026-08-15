require "rails_helper"

RSpec.describe "Email change", type: :system do
  let(:user) { create(:user) }

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    expect(page).to have_text(I18n.t("sessions.check_email.title"))
    token = MagicLinkToken.create_for_email(user.email_address)
    visit magic_link_callback_path(token: token)
    click_button I18n.t("magic_link_callbacks.confirm.sign_in_button")
    expect(page).to have_text(I18n.t("magic_link_callbacks.show.signed_in"))
  end

  describe "initiating an email change" do
    before do
      sign_in_via_form(user)
      visit edit_settings_profile_path
    end

    it "starts the change and shows the pending notice when the session is reauth-fresh" do
      fill_in I18n.t("settings.profiles.edit.email_label"), with: "new@example.com"
      click_button I18n.t("settings.profiles.edit.submit")

      expect(page).to have_text("new@example.com")
      expect(page).to have_text(I18n.t("settings.profiles.edit.cancel_email_change"))
    end

    it "asks for re-authentication first when the session is stale (SEC-2b)" do
      user.sessions.update_all(reauthenticated_at: 1.hour.ago)
      fill_in I18n.t("settings.profiles.edit.email_label"), with: "new@example.com"
      click_button I18n.t("settings.profiles.edit.submit")

      expect(page).to have_text(I18n.t("settings.reauthentications.new.title"))
      expect(user.reload.pending_email).to be_nil
    end

    it "updates name without password when email unchanged" do
      fill_in I18n.t("settings.profiles.edit.first_name_label"), with: "NewName"
      click_button I18n.t("settings.profiles.edit.submit")

      expect(page).to have_text(I18n.t("settings.profiles.update.success"))
      expect(user.reload.first_name).to eq("NewName")
    end
  end

  describe "confirming email change" do
    before do
      sign_in_via_form(user)
      Users::EmailChange.new(user).initiate!("confirmed@example.com")
      user.reload
    end

    it "updates email when clicking verification link" do
      visit settings_email_confirmation_path(token: user.pending_email_token)

      expect(page).to have_text(I18n.t("settings.email_confirmations.show.success"))
      expect(user.reload.email_address).to eq("confirmed@example.com")
    end

    it "rejects expired token" do
      user.update!(pending_email_sent_at: 25.hours.ago)
      visit settings_email_confirmation_path(token: user.pending_email_token)

      expect(page).to have_text(I18n.t("settings.email_confirmations.show.invalid_or_expired"))
      expect(user.reload.email_address).not_to eq("confirmed@example.com")
    end
  end

  describe "cancelling email change" do
    before do
      sign_in_via_form(user)
      Users::EmailChange.new(user).initiate!("cancel@example.com")
      visit edit_settings_profile_path
    end

    it "clears pending email" do
      click_link I18n.t("settings.profiles.edit.cancel_email_change")

      expect(page).to have_text(I18n.t("settings.email_confirmations.destroy.cancelled"))
      expect(user.reload.pending_email).to be_nil
      expect(page).not_to have_text("cancel@example.com")
    end
  end
end

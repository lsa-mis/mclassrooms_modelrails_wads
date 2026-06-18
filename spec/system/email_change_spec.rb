require "rails_helper"

RSpec.describe "Email change", type: :system do
  let(:user) { create(:user) }

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: "SecureP@ssw0rd123!"
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_text(I18n.t("sessions.create.success"))
  end

  describe "initiating an email change" do
    before do
      sign_in_via_form(user)
      visit edit_settings_profile_path
    end

    it "shows verification sent notice with correct password" do
      fill_in I18n.t("settings.profiles.edit.email_label"), with: "new@example.com"
      fill_in I18n.t("settings.profiles.edit.current_password_label"), with: "SecureP@ssw0rd123!"
      click_button I18n.t("settings.profiles.edit.submit")

      expect(page).to have_text("new@example.com")
      expect(page).to have_text(I18n.t("settings.profiles.edit.cancel_email_change"))
    end

    it "shows error with wrong password" do
      fill_in I18n.t("settings.profiles.edit.email_label"), with: "new@example.com"
      fill_in I18n.t("settings.profiles.edit.current_password_label"), with: "wrongpassword"
      click_button I18n.t("settings.profiles.edit.submit")

      expect(page).to have_css("[role='alert']")
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
      user.initiate_email_change!("confirmed@example.com", "SecureP@ssw0rd123!")
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
      user.initiate_email_change!("cancel@example.com", "SecureP@ssw0rd123!")
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

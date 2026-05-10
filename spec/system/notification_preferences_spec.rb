require "rails_helper"

RSpec.describe "Notification preferences", type: :system do
  let(:password) { "SecureP@ssw0rd123!" }
  let(:user) { create(:user, password: password) }

  def sign_in_via_form(user)
    visit new_session_path
    fill_in I18n.t("sessions.new.email_label"), with: user.email_address
    click_button I18n.t("sessions.new.continue")
    fill_in I18n.t("sessions.password_form.password_label"), with: password
    click_button I18n.t("sessions.password_form.submit")
    expect(page).to have_text(I18n.t("sessions.create.success"))
  end

  before do
    sign_in_via_form(user)
    user.create_preferences!(timezone: "America/New_York") unless user.preferences
    # Sign-in dispatches a SignInFromNewDeviceNotifier; clearing keeps the
    # bell-tooltip DND test deterministic about the unread count.
    user.notifications.destroy_all
  end

  describe "page render" do
    it "shows the master DND toggle, 5×3 matrix, digest controls, and retention dropdown" do
      visit edit_account_notification_preferences_path

      expect(page).to have_css("h1", text: I18n.t("notifications.preferences.heading"))
      # Master DND
      expect(page).to have_text(I18n.t("notifications.preferences.master_section"))
      # 5 categories × 3 channels = 15 toggle inputs (counting only non-disabled
      # ones, the security row has 2 disabled so 13 enabled).
      checkboxes = all('input[type="checkbox"][name^="notification_preferences"]', visible: :all)
      expect(checkboxes.size).to eq(16) # 1 DND + 15 matrix
      # Security in_app and email rendered as disabled
      expect(page).to have_css(
        'input[type="checkbox"][name="notification_preferences[categories][security][in_app]"][disabled]',
        visible: :all
      )
      # Digest cadence radio + time input
      expect(page).to have_css('input[type="radio"][name="notification_preferences[digest][cadence]"]', count: 2, visible: :all)
      expect(page).to have_css('input[type="time"][name="notification_preferences[digest][hour_local]"]', visible: :all)
      # Retention dropdown
      expect(page).to have_css('select[name="notification_preferences[retention_days]"]', visible: :all)
    end
  end

  describe "auto-save flow" do
    it "flips DND when the master toggle is clicked and persists" do
      visit edit_account_notification_preferences_path

      expect(user.preferences.notification_preferences["do_not_disturb"]).to eq(false)

      find('label[for^="toggle-notification-preferences-do-not-disturb"]', visible: :all).click

      # Wait for the auto-submit round-trip to complete by polling DB state.
      Timeout.timeout(5) do
        sleep 0.1 until user.preferences.reload.notification_preferences["do_not_disturb"] == true
      end
      expect(user.preferences.notification_preferences["do_not_disturb"]).to eq(true)
    end
  end

  describe "bell tooltip when DND is on" do
    it "shows the unread-with-dnd title on the bell when DND is active and user has unread" do
      # Seed DND on + an unread notification so the tooltip surfaces.
      user.preferences.update!(
        notification_preferences: user.preferences.notification_preferences.merge("do_not_disturb" => true)
      )
      PasswordChangedNotifier.with(record: user).deliver(user)

      visit root_path

      bell = find("button[data-notifications-bell-trigger]")
      expect(bell["title"]).to include("hidden")
    end

    it "omits the tooltip title when DND is off" do
      PasswordChangedNotifier.with(record: user).deliver(user)

      visit root_path

      bell = find("button[data-notifications-bell-trigger]")
      expect(bell["title"]).to be_nil.or eq("")
    end
  end
end

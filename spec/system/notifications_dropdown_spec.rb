require "rails_helper"

RSpec.describe "Notifications bell + dropdown", type: :system do
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

  # Deterministic delivery — sequential offsets keep every notification in
  # its own idempotency bucket without relying on `rand`. See
  # `project_flaky_tests_followup.md` for the rand-bucket-collision pattern
  # this avoids.
  def deliver_n_security_notifications(count, recipient: user)
    count.times do |i|
      travel_to(Time.current + ((i + 1) * 5).minutes) do
        PasswordChangedNotifier.with(record: recipient).deliver(recipient)
      end
    end
    recipient.notifications.reload.order(created_at: :asc).last(count)
  end

  before do
    sign_in_via_form(user)
    # Sign-in dispatches a SignInFromNewDeviceNotifier; destroy it so the
    # dropdown's "recent read" list (5 most recent) doesn't surface the
    # sign-in noise. Examples that need notifications create them
    # explicitly via `deliver_n_security_notifications`.
    user.notifications.destroy_all
  end

  describe "bell trigger in user menu" do
    it "renders an accessible bell button next to the avatar" do
      visit root_path

      expect(page).to have_css(
        "button[aria-label^='#{I18n.t('notifications.bell.label')}']",
        visible: :visible
      )
    end

    it "omits the unread badge when no notifications are unread" do
      visit root_path

      expect(page).not_to have_css("[data-notifications-bell-badge]", visible: :visible)
    end

    it "shows a numeric badge with the unread count" do
      deliver_n_security_notifications(3)

      visit root_path

      expect(page).to have_css(
        "[data-notifications-bell-badge]",
        text: "3",
        visible: :visible
      )
    end

    it "caps the badge text at 10+ when more than nine notifications are unread" do
      deliver_n_security_notifications(12)

      visit root_path

      expect(page).to have_css(
        "[data-notifications-bell-badge]",
        text: "10+",
        visible: :visible
      )
    end

    it "announces the count via aria-label" do
      deliver_n_security_notifications(2)

      visit root_path

      bell = find("button[data-notifications-bell-trigger]")
      expect(bell["aria-label"]).to include("2")
    end
  end

  describe "dropdown panel open/close" do
    it "opens when the bell is clicked and toggles aria-expanded" do
      visit root_path

      bell = find("button[data-notifications-bell-trigger]")
      expect(bell["aria-expanded"]).to eq("false")

      bell.click

      expect(page).to have_css(
        "[data-notification-dropdown-target='panel']",
        visible: :visible
      )
      expect(bell["aria-expanded"]).to eq("true")
    end

    it "closes when Escape is pressed" do
      visit root_path
      bell = find("button[data-notifications-bell-trigger]")
      bell.click
      expect(page).to have_css(
        "[data-notification-dropdown-target='panel']",
        visible: :visible
      )

      page.send_keys(:escape)

      expect(page).to have_no_css(
        "[data-notification-dropdown-target='panel']",
        visible: :visible
      )
      expect(bell["aria-expanded"]).to eq("false")
    end
  end

  describe "global keyboard shortcut" do
    # Programmatic KeyboardEvent dispatch goes through Playwright's
    # main-world execution context so the controller's document-level
    # listener fires. Capybara's `send_keys` doesn't reliably pierce
    # element focus + modifier-state on every driver — same workaround
    # the existing user_menu_spec uses for arrow keys.
    def fire_global_shortcut(key:, meta_key: false, ctrl_key: false, shift_key: false)
      page.driver.with_playwright_page do |pw_page|
        pw_page.evaluate(<<~JS)
          document.dispatchEvent(new KeyboardEvent("keydown", {
            key: "#{key}",
            metaKey: #{meta_key},
            ctrlKey: #{ctrl_key},
            shiftKey: #{shift_key},
            bubbles: true
          }))
        JS
      end
    end

    it "opens the dropdown via Cmd+Shift+N" do
      visit root_path
      bell = find("button[data-notifications-bell-trigger]")
      expect(bell["aria-expanded"]).to eq("false")

      fire_global_shortcut(key: "n", meta_key: true, shift_key: true)

      expect(page).to have_css(
        "[data-notification-dropdown-target='panel']",
        visible: :visible
      )
      expect(bell["aria-expanded"]).to eq("true")
    end

    it "opens the dropdown via Ctrl+Shift+N (cross-platform)" do
      visit root_path
      bell = find("button[data-notifications-bell-trigger]")

      fire_global_shortcut(key: "n", ctrl_key: true, shift_key: true)

      expect(bell["aria-expanded"]).to eq("true")
    end

    it "closes the dropdown when toggled while open" do
      visit root_path
      bell = find("button[data-notifications-bell-trigger]")
      bell.click
      expect(bell["aria-expanded"]).to eq("true")

      fire_global_shortcut(key: "n", meta_key: true, shift_key: true)

      expect(bell["aria-expanded"]).to eq("false")
    end
  end

  describe "dropdown content" do
    let(:expected_message) {
      I18n.t("notifications.password_changed.message", user_name: user.first_name)
    }

    it "renders recent notifications inside the panel" do
      deliver_n_security_notifications(2)

      visit root_path
      find("button[data-notifications-bell-trigger]").click

      within "[data-notification-dropdown-target='panel']" do
        items = all("[data-notification-item]")
        expect(items.size).to eq(2)
        items.each do |item|
          expect(item).to have_text(expected_message)
        end
      end
    end

    it "shows the empty state when there are no notifications" do
      visit root_path
      find("button[data-notifications-bell-trigger]").click

      within "[data-notification-dropdown-target='panel']" do
        expect(page).to have_text(I18n.t("notifications.bell.empty"))
      end
    end

    it "caps the visible list at 10 unread plus 5 most recent read" do
      deliver_n_security_notifications(12)
      # Mark the oldest 6 as read so we have 6 read + 6 unread.
      user.notifications.order(:created_at).limit(6).update_all(read_at: Time.current)

      visit root_path
      find("button[data-notifications-bell-trigger]").click

      within "[data-notification-dropdown-target='panel']" do
        items = all("[data-notification-item]")
        # 6 unread (under cap of 10) + 5 most recent read (cap of 5) = 11
        expect(items.size).to eq(11)
      end
    end
  end

  describe "click an item" do
    it "marks the notification as read and redirects to the notifier URL" do
      notification = deliver_n_security_notifications(1).first
      expect(notification.read_at).to be_nil

      visit root_path
      find("button[data-notifications-bell-trigger]").click
      within "##{ActionView::RecordIdentifier.dom_id(notification, :dropdown)}" do
        find("a").click
      end

      # PasswordChangedNotifier#url returns account_connected_accounts_path
      expect(page).to have_current_path(account_connected_accounts_path)
      expect(notification.reload.read_at).to be_present
    end
  end

  # The shared header (and therefore the bell + dropdown) renders inside the
  # markdowndocs engine layout when a signed-in user visits /docs/*. Engine
  # views run in their own routing context, so any unprefixed main-app route
  # helper (account_notifications_path, open_account_notification_path) raises
  # NameError. The dropdown partial must use `main_app.` like every other
  # shared partial does.
  describe "rendering inside the markdowndocs engine" do
    it "renders without raising on /docs and links 'see all' to the main-app route" do
      notification = deliver_n_security_notifications(1).first

      visit "/docs/getting-started"

      expect(page).to have_css("article", text: /Getting Started/i)
      expect(page).to have_css("button[data-notifications-bell-trigger]")

      find("button[data-notifications-bell-trigger]").click

      within "[data-notification-dropdown-target='panel']" do
        see_all = find_link(I18n.t("notifications.bell.see_all"))
        expect(see_all[:href]).to end_with(account_notifications_path)

        item_link = find("##{ActionView::RecordIdentifier.dom_id(notification, :dropdown)} a")
        expect(item_link[:href]).to end_with(open_account_notification_path(notification))
      end
    end
  end
end

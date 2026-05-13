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

  describe "axe-core WCAG 2.2 AAA audit" do
    let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

    it "passes AAA audit when the dropdown is open with notifications visible" do
      deliver_n_security_notifications(2)

      visit root_path
      find("button[data-notifications-bell-trigger]").click
      expect(page).to have_css(
        "[data-notification-dropdown-target='panel']",
        visible: :visible
      )

      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "AAA violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end

    it "passes AAA audit when the dropdown shows the empty state" do
      visit root_path
      find("button[data-notifications-bell-trigger]").click

      within "[data-notification-dropdown-target='panel']" do
        expect(page).to have_text(I18n.t("notifications.bell.empty"))
      end

      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "AAA violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end

  # The shared header (and therefore the bell + dropdown) renders inside the
  # markdowndocs engine layout when a signed-in user visits /docs/*. Engine
  # Arrow-key cycling through dropdown items so keyboard-only users don't have
  # to Tab through unrelated chrome to reach each notification. Mirrors the
  # user-menu pattern (see spec/system/user_menu_spec.rb). The Playwright
  # KeyboardEvent dispatch doesn't reliably reach Stimulus listeners through
  # main-world boundaries, so we invoke the controller's handleKeydown
  # directly — same workaround the user-menu spec documents.
  describe "arrow-key navigation within the open dropdown" do
    def send_dropdown_key(key)
      page.driver.with_playwright_page do |pw_page|
        pw_page.evaluate(<<~JS)
          (function() {
            var el = document.querySelector('[data-controller~="notification-dropdown"]');
            var c = window.Stimulus.getControllerForElementAndIdentifier(el, 'notification-dropdown');
            if (c) c.handleKeydown(new KeyboardEvent('keydown', { key: '#{key}', bubbles: true }));
          })()
        JS
      end
    end

    def focused_dom_id
      page.evaluate_script("document.activeElement?.closest('[data-notification-item]')?.id || document.activeElement?.id")
    end

    it "focuses the first notification item when the dropdown opens" do
      notifications = deliver_n_security_notifications(3)
      visit root_path
      find("button[data-notifications-bell-trigger]").click

      first_dom_id = ActionView::RecordIdentifier.dom_id(notifications.last, :dropdown)
      expect(focused_dom_id).to eq(first_dom_id)
    end

    it "ArrowDown moves focus to the next item" do
      notifications = deliver_n_security_notifications(3)
      visit root_path
      find("button[data-notifications-bell-trigger]").click

      send_dropdown_key("ArrowDown")

      second_newest = notifications.reverse[1]
      expect(focused_dom_id).to eq(ActionView::RecordIdentifier.dom_id(second_newest, :dropdown))
    end

    it "ArrowDown wraps from last item back to the first" do
      notifications = deliver_n_security_notifications(3)
      visit root_path
      find("button[data-notifications-bell-trigger]").click

      3.times { send_dropdown_key("ArrowDown") }

      first_dom_id = ActionView::RecordIdentifier.dom_id(notifications.last, :dropdown)
      expect(focused_dom_id).to eq(first_dom_id)
    end

    it "ArrowUp wraps from the first item back to the last" do
      notifications = deliver_n_security_notifications(3)
      visit root_path
      find("button[data-notifications-bell-trigger]").click

      send_dropdown_key("ArrowUp")

      last_dom_id = ActionView::RecordIdentifier.dom_id(notifications.first, :dropdown)
      expect(focused_dom_id).to eq(last_dom_id)
    end

    it "Home key focuses the first item" do
      notifications = deliver_n_security_notifications(3)
      visit root_path
      find("button[data-notifications-bell-trigger]").click
      send_dropdown_key("ArrowDown")
      send_dropdown_key("ArrowDown")

      send_dropdown_key("Home")

      first_dom_id = ActionView::RecordIdentifier.dom_id(notifications.last, :dropdown)
      expect(focused_dom_id).to eq(first_dom_id)
    end

    it "End key focuses the last item" do
      notifications = deliver_n_security_notifications(3)
      visit root_path
      find("button[data-notifications-bell-trigger]").click

      send_dropdown_key("End")

      last_dom_id = ActionView::RecordIdentifier.dom_id(notifications.first, :dropdown)
      expect(focused_dom_id).to eq(last_dom_id)
    end

    it "is a no-op when the dropdown is empty (no items, no focus change)" do
      visit root_path
      find("button[data-notifications-bell-trigger]").click

      trigger_id_before = page.evaluate_script("document.activeElement?.getAttribute('data-notifications-bell-trigger')")

      send_dropdown_key("ArrowDown")
      send_dropdown_key("End")

      trigger_id_after = page.evaluate_script("document.activeElement?.getAttribute('data-notifications-bell-trigger')")
      expect(trigger_id_after).to eq(trigger_id_before)
    end

    # Focus restoration after a broadcast lands. Without this, a SR user
    # tab-navigating through items would lose their place every time the
    # dropdown frame re-rendered (e.g., a new notification arriving, or
    # a cross-tab read-state change). The Stimulus controller hooks
    # turbo:before-stream-render to capture the focused item's dom id
    # and restore focus to the same id after the replacement completes.
    it "preserves focus on the same notification item after a broadcast re-renders the dropdown list" do
      notifications = deliver_n_security_notifications(3)
      visit root_path
      find("button[data-notifications-bell-trigger]").click

      # Move focus to the second-newest item via arrow nav.
      send_dropdown_key("ArrowDown")
      focused_item_id = page.evaluate_script(
        "document.activeElement?.closest('[data-notification-item]')?.id"
      )
      expect(focused_item_id).not_to be_nil

      # Trigger a fresh notification — broadcasts a dropdown frame replace.
      # Use a far-future offset to avoid colliding with the existing
      # idempotency buckets from deliver_n_security_notifications.
      travel_to(Time.current + 99.minutes) do
        PasswordChangedNotifier.with(record: user).deliver(user)
      end

      # Wait for the dropdown to grow by 1 item (the broadcast landed).
      using_wait_time(5) do
        expect(page).to have_css("[data-notification-item]", minimum: 4)
      end

      # Focus must still be on the item with the same dom id — proves
      # focus was captured pre-render and reapplied post-render.
      preserved_focused_id = page.evaluate_script(
        "document.activeElement?.closest('[data-notification-item]')?.id"
      )
      expect(preserved_focused_id).to eq(focused_item_id)
    end
  end

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

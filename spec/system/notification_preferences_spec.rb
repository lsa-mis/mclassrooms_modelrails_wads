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

  describe "page render (four-card layout)" do
    before { visit edit_settings_notification_preferences_path }

    it "renders the page heading" do
      expect(page).to have_css("h1", text: I18n.t("settings.pages.notifications.h1"))
    end

    it "renders Card 1: Notification Types with 5 rows + security 'Always on' badge" do
      expect(page).to have_css("h2", text: I18n.t("notifications.preferences.notification_types.heading"))
      # 5 type toggles (security disabled-but-rendered + 4 user-toggleable).
      checkboxes = all('input[type="checkbox"][name^="notification_preferences[notification_types]"]', visible: :all)
      expect(checkboxes.size).to eq(5)
      # Security row is disabled and shows the always-on reassurance.
      expect(page).to have_css(
        'input[type="checkbox"][name="notification_preferences[notification_types][security]"][disabled]',
        visible: :all
      )
      expect(page).to have_text(I18n.t("notifications.preferences.notification_types.always_on"))
    end

    it "renders Card 2: Delivery Method with in_app + email rows + frequency select" do
      expect(page).to have_css("h2", text: I18n.t("notifications.preferences.delivery_methods.heading"))
      expect(page).to have_css(
        'input[type="checkbox"][name="notification_preferences[delivery_methods][in_app][enabled]"]',
        visible: :all
      )
      expect(page).to have_css(
        'input[type="checkbox"][name="notification_preferences[delivery_methods][email][enabled]"]',
        visible: :all
      )
      # Email row has the frequency select with the three valid options.
      expect(page).to have_css(
        'select[name="notification_preferences[delivery_methods][email][frequency]"]',
        visible: :all
      )
      %w[instant daily weekly].each do |freq|
        expect(page).to have_css(
          %Q(select[name="notification_preferences[delivery_methods][email][frequency]"] option[value="#{freq}"]),
          visible: :all
        )
      end
    end

    it "renders Card 3: Quiet Hours with toggle + start/end time inputs + day picker + reassurance text" do
      expect(page).to have_css("h2", text: I18n.t("notifications.preferences.quiet_hours.heading"))
      expect(page).to have_css(
        'input[type="checkbox"][name="notification_preferences[quiet_hours][enabled]"]',
        visible: :all
      )
      expect(page).to have_css(
        'input[type="time"][name="notification_preferences[quiet_hours][start]"]',
        visible: :all
      )
      expect(page).to have_css(
        'input[type="time"][name="notification_preferences[quiet_hours][end]"]',
        visible: :all
      )
      # Per-weekday day picker: 7 checkboxes (one per day) + 1 hidden empty
      # sentinel so the array param is always submitted = 8 total inputs
      # under the `active_days[]` name.
      day_checkboxes = all(
        'input[name="notification_preferences[quiet_hours][active_days][]"]',
        visible: :all
      )
      expect(day_checkboxes.size).to eq(8)
      # Hidden sentinel (empty value) ensures unchecking-all submits as [""].
      expect(page).to have_css(
        'input[type="hidden"][name="notification_preferences[quiet_hours][active_days][]"][value=""]',
        visible: :all
      )
      # All 7 day-name checkboxes by value.
      %w[monday tuesday wednesday thursday friday saturday sunday].each do |day|
        expect(page).to have_css(
          %Q(input[type="checkbox"][name="notification_preferences[quiet_hours][active_days][]"][value="#{day}"]),
          visible: :all
        )
      end
      # Fixed reassurance text (decision #6: NOT a toggle, just a guarantee).
      expect(page).to have_text(I18n.t("notifications.preferences.quiet_hours.security_reassurance"))
    end

    it "renders Card 4: Advanced with the retention dropdown" do
      expect(page).to have_css("h2", text: I18n.t("notifications.preferences.advanced.heading"))
      expect(page).to have_css(
        'select[name="notification_preferences[retention_days]"]',
        visible: :all
      )
    end
  end

  describe "auto-save flow" do
    it "flips quiet_hours.enabled when the toggle is clicked and persists" do
      visit edit_settings_notification_preferences_path

      expect(user.preferences.notification_preferences.dig("quiet_hours", "enabled")).to eq(false)

      find('label[for^="toggle-notification-preferences-quiet-hours-enabled"]', visible: :all).click

      # Wait for the auto-submit round-trip to complete by polling DB state.
      Timeout.timeout(5) do
        sleep 0.1 until user.preferences.reload.notification_preferences.dig("quiet_hours", "enabled") == true
      end
      expect(user.preferences.notification_preferences.dig("quiet_hours", "enabled")).to eq(true)
    end
  end

  describe "toggle visual feedback" do
    # The bug this guards: prior to using peer-checked: variants, the pill's
    # knob position was computed in Ruby at render time. Clicks updated the
    # invisible checkbox but the track/knob classes never refreshed, so the
    # pill appeared frozen even though the data was saved correctly. We
    # measure the knob's bounding-rect to be CSS-implementation-agnostic.
    it "moves the pill's knob horizontally when the toggle is clicked" do
      visit edit_settings_notification_preferences_path

      toggle_label = find(
        'label[for^="toggle-notification-preferences-quiet-hours-enabled"]',
        visible: :all
      )
      toggle_id = toggle_label[:for]

      knob_left_js = <<~JS
        document.getElementById('#{toggle_id}')
                .closest('label')
                .querySelector('span > span')
                .getBoundingClientRect().left
      JS

      initial_x = page.evaluate_script(knob_left_js)

      toggle_label.click

      moved = false
      Timeout.timeout(2) do
        sleep 0.05 until (moved = page.evaluate_script(knob_left_js) != initial_x)
      end

      expect(moved).to eq(true), "Toggle pill knob did not move after click — visual feedback is broken"
    end
  end

  describe "timezone change drawer closes on save" do
    # Prior to fix: TimezonesController returned 204 No Content for every
    # path including the explicit-user-save flow, so Turbo got an empty
    # response and the <details> drawer stayed open, the summary still
    # showed the OLD timezone, and there was no save confirmation. Now
    # the override path returns a Turbo Stream that re-renders the
    # timezone surface (no `open` attribute, new value in summary) and
    # updates the page-level aria-live region.
    it "closes the drawer + updates the visible timezone summary on save" do
      user.preferences.update!(timezone: "America/Chicago")
      visit edit_settings_notification_preferences_path

      # Open the drawer by clicking the summary.
      find("summary", text: I18n.t("notifications.preferences.timezone.heading", default: "Your timezone")).click
      expect(page).to have_css("details[open]", count: 1)

      # Pick a different timezone and save. Option labels are the raw IANA
      # identifier (the picker helper uses no friendly-label mapping).
      within "details[open]" do
        select "America/Los_Angeles", from: I18n.t("notifications.preferences.timezone.picker_label")
        click_button I18n.t("notifications.preferences.timezone.save")
      end

      # Drawer closes (no details element has the `open` attribute).
      expect(page).to have_no_css("details[open]")
      # Summary reflects the new value without a page reload.
      expect(page).to have_text("America/Los_Angeles")
      # Server-side persistence.
      expect(user.preferences.reload.timezone).to eq("America/Los_Angeles")
    end
  end

  describe "quiet hours: deceptive enabled-with-zero-days warning" do
    # The value object treats active_days: [] as "quiet hours never active"
    # (see app/lib/notification_preferences.rb:99-102). When the user has
    # the QH toggle enabled BUT no day chips checked, the runtime is
    # silently off — the toggle is misleading. A warning surfaces the
    # contradiction so the user can either re-check a day or disable QH.
    def set_quiet_hours(enabled:, active_days:)
      user.preferences.update!(
        notification_preferences: user.preferences.notification_preferences.merge(
          "quiet_hours" => { "enabled" => enabled, "active_days" => active_days }
        )
      )
    end

    it "shows the warning when quiet hours are enabled with zero active days" do
      set_quiet_hours(enabled: true, active_days: [])
      visit edit_settings_notification_preferences_path

      expect(page).to have_text(I18n.t("notifications.preferences.quiet_hours.empty_days_warning"))
    end

    it "hides the warning when quiet hours are enabled with at least one active day" do
      set_quiet_hours(enabled: true, active_days: %w[monday wednesday friday])
      visit edit_settings_notification_preferences_path

      expect(page).not_to have_text(I18n.t("notifications.preferences.quiet_hours.empty_days_warning"))
    end

    it "hides the warning when quiet hours are disabled regardless of days" do
      set_quiet_hours(enabled: false, active_days: [])
      visit edit_settings_notification_preferences_path

      expect(page).not_to have_text(I18n.t("notifications.preferences.quiet_hours.empty_days_warning"))
    end

    it "live: clicking the last checked day to uncheck it reveals the warning without reload" do
      set_quiet_hours(enabled: true, active_days: %w[monday])
      visit edit_settings_notification_preferences_path

      expect(page).not_to have_text(I18n.t("notifications.preferences.quiet_hours.empty_days_warning"))

      # Click the Monday chip label to uncheck the underlying sr-only checkbox.
      find('label[for="quiet-hours-active-day-monday"]').click

      expect(page).to have_text(I18n.t("notifications.preferences.quiet_hours.empty_days_warning"))
    end
  end

  describe "screen-reader semantic relationships (panel-review accessibility cluster)" do
    # When a toggle is rendered as disabled-but-always-on (the security
    # category), the visual help text says "Always on" — but without
    # programmatic association, SR users hear "Security, dimmed, checked"
    # with no idea why it's locked. aria-describedby points at the help
    # span so it's announced together with the control.
    it "the disabled+always-on security toggle has aria-describedby linking to its help text" do
      visit edit_settings_notification_preferences_path

      security_checkbox = find(
        'input[type="checkbox"][name="notification_preferences[notification_types][security]"][disabled]',
        visible: :all
      )
      described_by_id = security_checkbox["aria-describedby"]
      expect(described_by_id).to be_present, "security toggle must describe its disabled state to SR users"
      help = find("##{described_by_id}", visible: :all)
      expect(help.text).to include(I18n.t("notifications.preferences.notification_types.always_on"))
    end

    # When the deceptive empty-active-days state is visible, the warning
    # explains what's wrong. SR users navigating the day-chip fieldset
    # have no signal the warning is tied to *this* fieldset — fix via
    # fieldset[aria-describedby] pointing at the warning's id.
    it "the Quiet Hours day-chip fieldset references the empty-days warning via aria-describedby" do
      user.preferences.update!(
        notification_preferences: user.preferences.notification_preferences.merge(
          "quiet_hours" => { "enabled" => true, "active_days" => [] }
        )
      )
      visit edit_settings_notification_preferences_path

      fieldset = find("fieldset", text: I18n.t("notifications.preferences.quiet_hours.active_days_label"))
      described_by_id = fieldset["aria-describedby"]
      expect(described_by_id).to be_present, "fieldset must point at the warning so SR users link the two"
      warning = find("##{described_by_id}")
      expect(warning.text).to include(I18n.t("notifications.preferences.quiet_hours.empty_days_warning"))
    end

    # A role=status live region only announces reliably when it is already in
    # the accessibility tree before its content appears. Toggling display on
    # the live region itself (the prior shape — role=status sat on the hidden
    # <p>) is the known-unreliable pattern Léonie flagged: the element pops
    # into existence and SRs may not fire. The warning must instead live inside
    # a STABLE wrapper that stays in the tree even while the warning is hidden.
    it "announces the empty-days warning via a stable live region, not by toggling the live region itself" do
      # Quiet hours disabled = warning hidden = the common case. The live
      # region must still be present and unhidden so a later reveal announces.
      user.preferences.update!(
        notification_preferences: user.preferences.notification_preferences.merge(
          "quiet_hours" => { "enabled" => false, "active_days" => [] }
        )
      )
      visit edit_settings_notification_preferences_path

      warning = find("#quiet-hours-empty-days-warning", visible: :all)
      expect(warning[:role]).to be_blank,
        "the toggled warning <p> must not itself be the live region — a display:none region announces unreliably"

      live_region = warning.find(:xpath, "ancestor::*[@role='status'][1]")
      expect(live_region["aria-live"]).to eq("polite"),
        "the warning must sit inside a role=status aria-live=polite wrapper"
      expect(live_region[:class].to_s).not_to include("hidden"),
        "the live region wrapper must stay in the a11y tree (never hidden) so revealing the warning is announced"
    end
  end

  # Bell-tooltip DND tests removed: the new avatar-bell design surfaces
  # only severity on the bell overlay (which is aria-hidden). DND state is
  # canonical on the preferences page; the bell never surfaces it. See
  # docs/superpowers/specs/2026-05-15-avatar-bell-notification-indicator-design.md
  # ("Resolved decisions: DND is not surfaced on the bell").
end

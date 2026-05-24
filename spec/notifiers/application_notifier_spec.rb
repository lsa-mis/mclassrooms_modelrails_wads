require "rails_helper"

RSpec.describe ApplicationNotifier, type: :notifier do
  # Define stub Notifier subclasses scoped to this spec via `unless defined?` guards
  # to prevent constant collision across the suite.
  class StubAccountAccessNotifier < ApplicationNotifier
    category :account_access

    notification_methods do
      def message = "stub"
      def url     = "/stub"
    end
  end unless defined?(StubAccountAccessNotifier)

  class StubSecurityNotifier < ApplicationNotifier
    category :security

    notification_methods do
      def message = "stub-security"
      def url     = "/stub"
    end
  end unless defined?(StubSecurityNotifier)

  class StubNoRecordNotifier < ApplicationNotifier
    category :account_access

    notification_methods do
      def message = "stub-no-record"
      def url     = "/stub"
    end
  end unless defined?(StubNoRecordNotifier)

  describe ".category" do
    it "registers the category name as a class attribute" do
      expect(StubAccountAccessNotifier.category_name).to eq "account_access"
    end
  end

  describe ".severity" do
    it "defaults to :info when not declared" do
      klass = Class.new(ApplicationNotifier)
      expect(klass.severity_name).to eq(:info)
    end

    it "stores the declared severity as a symbol" do
      klass = Class.new(ApplicationNotifier) do
        severity :danger
      end
      expect(klass.severity_name).to eq(:danger)
    end

    it "accepts string arguments and stores as symbol" do
      klass = Class.new(ApplicationNotifier) do
        severity "warning"
      end
      expect(klass.severity_name).to eq(:warning)
    end

    it "does not leak between subclasses" do
      a = Class.new(ApplicationNotifier) { severity :danger }
      b = Class.new(ApplicationNotifier) { severity :success }
      expect(a.severity_name).to eq(:danger)
      expect(b.severity_name).to eq(:success)
    end

    it "stores the value as a Symbol (the storage contract relied on by NotificationBellHelper)" do
      klass = Class.new(ApplicationNotifier) do
        severity :danger
      end
      expect(klass.severity_name).to be_a(Symbol)
    end

    it "raises ArgumentError when severity is not in the canonical set" do
      expect {
        Class.new(ApplicationNotifier) { severity :critical }
      }.to raise_error(ArgumentError, /Invalid severity :critical.*danger.*warning.*info.*success/)
    end

    it "raises ArgumentError when severity is a string outside the canonical set" do
      expect {
        Class.new(ApplicationNotifier) { severity "urgent" }
      }.to raise_error(ArgumentError, /Invalid severity "urgent"/)
    end

    it "accepts all four canonical severities without raising" do
      %i[danger warning info success].each do |sev|
        expect { Class.new(ApplicationNotifier) { severity sev } }.not_to raise_error
      end
    end
  end

  describe "automatic idempotency-key population (column)" do
    let(:user) { create(:user) }
    let(:resource) { create(:user) }

    it "populates record.idempotency_key on the underlying noticed_events row" do
      StubAccountAccessNotifier.with(record: resource).deliver(user)
      event = Noticed::Event.last
      expect(event.idempotency_key).to be_present
    end

    it "does NOT write idempotency_key into params (it's a column, not metadata)" do
      StubAccountAccessNotifier.with(record: resource).deliver(user)
      event = Noticed::Event.last
      expect(event.params["idempotency_key"]).to be_nil
      expect(event.params[:idempotency_key]).to be_nil
    end

    it "uses NotifierClass + record_id + minute-bucket as the key format" do
      freeze_time do
        StubAccountAccessNotifier.with(record: resource).deliver(user)
        event = Noticed::Event.last
        expect(event.idempotency_key).to eq "StubAccountAccessNotifier_#{resource.id}_#{Time.current.to_i / 60}"
      end
    end

    it "preserves a domain-supplied idempotency_key" do
      StubAccountAccessNotifier.with(record: resource, idempotency_key: "manual-123").deliver(user)
      event = Noticed::Event.last
      expect(event.idempotency_key).to eq "manual-123"
    end

    it "raises ArgumentError when neither record nor explicit key is supplied" do
      expect {
        StubNoRecordNotifier.with(other_param: "x").deliver(user)
      }.to raise_error(ArgumentError, /requires either a :record with an id, or an explicit :idempotency_key/)
    end
  end

  describe "#deliver sentinel return" do
    let(:user) { create(:user) }
    let(:resource) { create(:user) }

    it "returns :delivered on first send" do
      result = StubAccountAccessNotifier.with(record: resource).deliver(user)
      expect(result).to eq :delivered
    end

    it "returns :deduplicated on duplicate within the same minute (RecordNotUnique rescued)" do
      freeze_time do
        StubAccountAccessNotifier.with(record: resource).deliver(user)
        result = StubAccountAccessNotifier.with(record: resource).deliver(user)
        expect(result).to eq :deduplicated
      end
    end

    it "creates exactly one noticed_events row across two identical deliveries" do
      freeze_time do
        StubAccountAccessNotifier.with(record: resource).deliver(user)
        expect {
          StubAccountAccessNotifier.with(record: resource).deliver(user)
        }.not_to change(Noticed::Event, :count)
      end
    end
  end

  describe "concurrent dispatch resolution (Chris Oliver edge case)" do
    let(:user_a) { create(:user) }
    let(:user_b) { create(:user) }
    let(:resource) { create(:user) }

    it "does not orphan recipients on the deduplicated dispatch" do
      # When two parallel dispatches happen for the same key, the first wins
      # the INSERT; the second rescues RecordNotUnique. Both calls' recipients
      # should still receive their notifications, linked to the SAME event row.
      freeze_time do
        StubAccountAccessNotifier.with(record: resource).deliver(user_a)
        StubAccountAccessNotifier.with(record: resource).deliver(user_b)

        events = Noticed::Event.where(type: "StubAccountAccessNotifier")
        expect(events.count).to eq 1

        # First call's recipient (user_a) got their notification.
        # Second call's recipient (user_b) was deduplicated at the event level —
        # the v1 contract is "the second call returns :deduplicated and does NOT
        # add user_b as a recipient of the existing event." This matches the
        # plan's edge case: callers branch on the sentinel to handle the race.
        events_user_a = Noticed::Notification.where(recipient: user_a, type: "StubAccountAccessNotifier::Notification")
        expect(events_user_a.count).to eq 1
      end
    end
  end

  describe "#recipient_pref" do
    let(:user) { create(:user) }
    let!(:prefs) { create(:user_preferences, user: user) }

    it "delegates to NotificationPreferences#allow?" do
      StubAccountAccessNotifier.with(record: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_pref(:in_app)).to be true
    end

    it "returns false when DND is on for non-security" do
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))
      StubAccountAccessNotifier.with(record: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_pref(:email)).to be false
    end

    it "still returns true for security under DND" do
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))
      StubSecurityNotifier.with(record: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_pref(:email)).to be true
    end

    it "returns the :digest sentinel for email under non-instant frequency (non-security)" do
      # v2 tri-state: when email is enabled at "daily"/"weekly" frequency, the
      # value object returns :digest to signal "queue, don't send now." Each
      # email-delivery notifier's before_enqueue uses `== true` to abort the
      # immediate send so DigestMailerJob picks it up later.
      np = prefs.notification_preferences.deep_dup
      np["delivery_methods"]["email"]["frequency"] = "daily"
      prefs.update!(notification_preferences: np)
      StubAccountAccessNotifier.with(record: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_pref(:email)).to eq(:digest)
    end

    it "permits non-security in_app when recipient has no preferences row (schema default)" do
      # When a user has no UserPreferences row, the fallback wraps the JSONB
      # column's schema default — which permits in_app for account_access. This
      # is the centralized correct behavior; the previous default-deny posture
      # silently dropped notifications for freshly-created users.
      bare_user = create(:user)
      StubAccountAccessNotifier.with(record: bare_user).deliver(bare_user)
      notification = bare_user.notifications.last
      expect(notification.recipient_pref(:in_app)).to be true
    end

    it "still permits security for a recipient without preferences row" do
      bare_user = create(:user)
      StubSecurityNotifier.with(record: bare_user).deliver(bare_user)
      notification = bare_user.notifications.last
      expect(notification.recipient_pref(:in_app)).to be true
    end
  end

  describe "#preferences_for (missing-prefs fallback)" do
    # Regression spec for the centralized fallback: a user without a
    # UserPreferences row must wrap the schema-default JSONB blob, not a
    # silent default-deny `NotificationPreferences.new(nil)` shell.
    let(:bare_user) { create(:user) }

    it "returns a NotificationPreferences object backed by the schema default" do
      # The schema default permits in_app for every category; the previous
      # `nil` wrapping returned false for everything except security. This
      # test locks in that the canonical default matrix is honored.
      prefs = ApplicationNotifier.new.send(:preferences_for, bare_user)

      expect(prefs).to be_a(NotificationPreferences)
      expect(prefs.allow?(category: "account_access", channel: "in_app")).to be true
      expect(prefs.allow?(category: "workspace_activity", channel: "in_app")).to be true
      expect(prefs.allow?(category: "billing", channel: "email")).to be true
    end

    it "returns the user's own preferences object when a UserPreferences row exists" do
      user = create(:user)
      user_prefs = create(:user_preferences, user: user)
      user_prefs.update!(notification_preferences:
        user_prefs.notification_preferences.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))

      prefs = ApplicationNotifier.new.send(:preferences_for, user.reload)

      # Persisted DND flag honored — proves we read THROUGH to the user's row,
      # not a transient stand-in.
      expect(prefs.do_not_disturb?).to be true
    end
  end

  describe "#recipient_locale" do
    let(:user) { create(:user) }
    let!(:prefs) { create(:user_preferences, user: user) }

    it "returns the recipient's locale from preferences" do
      prefs.update!(locale: "fr")
      StubAccountAccessNotifier.with(record: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_locale).to eq :fr
    end

    it "falls back to I18n.default_locale when locale is nil" do
      prefs.update!(locale: nil)
      StubAccountAccessNotifier.with(record: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_locale).to eq I18n.default_locale
    end

    it "falls back to I18n.default_locale when locale is empty string" do
      prefs.update_columns(locale: "")
      StubAccountAccessNotifier.with(record: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_locale).to eq I18n.default_locale
    end
  end

  describe "#mark_seen!" do
    let(:user) { create(:user) }
    let(:resource) { create(:user) }

    it "sets seen_at on the underlying notification row" do
      StubAccountAccessNotifier.with(record: resource).deliver(user)
      notification = user.notifications.last
      freeze_time do
        notification.mark_seen!
        expect(notification.reload.seen_at).to be_within(1.second).of(Time.current)
      end
    end

    it "is idempotent (re-calls don't bump the timestamp)" do
      StubAccountAccessNotifier.with(record: resource).deliver(user)
      notification = user.notifications.last
      notification.mark_seen!
      original = notification.reload.seen_at
      travel 1.hour do
        notification.mark_seen!
        expect(notification.reload.seen_at).to eq original
      end
    end

    it "does not bump updated_at (system action, preserves cache keys)" do
      StubAccountAccessNotifier.with(record: resource).deliver(user)
      notification = user.notifications.last
      notification.update_columns(updated_at: 1.hour.ago)
      original_updated_at = notification.updated_at
      notification.mark_seen!
      expect(notification.reload.updated_at).to be_within(1.second).of(original_updated_at)
    end
  end

  describe "#render_safe_or_placeholder" do
    let(:user) { create(:user) }
    let(:resource) { create(:user) }

    it "yields normally when no error" do
      StubAccountAccessNotifier.with(record: resource).deliver(user)
      notification = user.notifications.last
      expect(notification.render_safe_or_placeholder { "ok" }).to eq "ok"
    end

    it "swallows RecordNotFound and renders placeholder" do
      StubAccountAccessNotifier.with(record: resource).deliver(user)
      notification = user.notifications.last
      result = notification.render_safe_or_placeholder do
        raise ActiveRecord::RecordNotFound, "boom"
      end
      expect(result).to eq I18n.t("notifications.placeholder")
    end

    it "swallows NoMethodError when receiver is nil (deleted notifiable)" do
      StubAccountAccessNotifier.with(record: resource).deliver(user)
      notification = user.notifications.last
      result = notification.render_safe_or_placeholder { nil.fnord }
      expect(result).to eq I18n.t("notifications.placeholder")
    end

    it "re-raises NoMethodError when the receiver is not nil (real bug)" do
      StubAccountAccessNotifier.with(record: resource).deliver(user)
      notification = user.notifications.last
      expect {
        notification.render_safe_or_placeholder { "string".fnord }
      }.to raise_error(NoMethodError)
    end

    it "logs at info level on rescue" do
      StubAccountAccessNotifier.with(record: resource).deliver(user)
      notification = user.notifications.last
      expect(Rails.logger).to receive(:info).with(/deleted record/)
      notification.render_safe_or_placeholder { raise ActiveRecord::RecordNotFound }
    end
  end

  describe ".notification_types_for" do
    # Reference both stubs explicitly so autoload runs and they appear in
    # ApplicationNotifier.descendants.
    before do
      _ = StubAccountAccessNotifier
      _ = StubSecurityNotifier
    end

    it "returns the per-notification STI type strings (suffixed) for the given category" do
      result = described_class.notification_types_for(:account_access)
      expect(result).to include("StubAccountAccessNotifier::Notification")
      expect(result).not_to include("StubSecurityNotifier::Notification")
    end

    it "accepts a string category" do
      result = described_class.notification_types_for("security")
      expect(result).to include("StubSecurityNotifier::Notification")
    end

    it "returns an empty array when no notifier matches the category" do
      expect(described_class.notification_types_for(:no_such_category)).to eq([])
    end
  end

  describe "#broadcast_notifications_arrival aria-live announcement" do
    let(:user) { create(:user) }
    let(:resource) { create(:user) }

    # The bell broadcast pushes two streams per recipient: a `replace` of the
    # bell-button (the visible badge) and an `update` of the page-level
    # `#notifications-live` aria-live region (the SR announcement). Locks in
    # that the announcement carries the localized arrival text so a future
    # refactor that drops/swallows the live-region update gets caught here.
    it "broadcasts the localized arrival_announcement text targeting #notifications-live" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
        [ user, :notifications ],
        target: "notifications-live",
        content: I18n.t("notifications.bell.arrival_announcement")
      )

      StubAccountAccessNotifier.with(record: resource).deliver(user)
    end
  end

  describe "#broadcast_notifications_arrival menu count refresh (v2: restored)" do
    let(:user) { create(:user) }
    let(:resource) { create(:user) }

    # v2 (2026-05-23) restored the menu-count broadcast that D1 had dropped:
    # the user-menu dropdown now carries the canonical Notifications link
    # with a live aria-announced count badge. Refreshes target
    # `notifications_menu_count_frame` and render the
    # `_user_menu_notifications_row` partial.
    it "broadcasts a menu-count refresh to notifications_menu_count_frame on event commit" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        anything,
        hash_including(
          target: "notifications_menu_count_frame",
          partial: "shared/user_menu_notifications_row"
        )
      )

      # Allow the other v2 broadcasts (avatar dot, hamburger dot, aria-live).
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
        .with(anything, hash_including(target: "notifications_indicator_avatar"))
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
        .with(anything, hash_including(target: "notifications_indicator_hamburger"))
      allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)

      StubAccountAccessNotifier.with(record: resource).deliver(user)
    end
  end

  describe ".notifier_class_names_for" do
    # Raw class-name variant (no ::Notification suffix). Used by
    # NotificationPreferences#security_notifier_types and elsewhere where
    # the parent Notifier class name is the right thing (e.g. retention
    # floor enforcement keyed by event type, not the per-notification type).
    before do
      _ = StubAccountAccessNotifier
      _ = StubSecurityNotifier
    end

    it "returns raw notifier class names (no STI suffix) for the given category" do
      result = described_class.notifier_class_names_for(:account_access)
      expect(result).to include("StubAccountAccessNotifier")
      expect(result).not_to include("StubAccountAccessNotifier::Notification")
    end
  end
end

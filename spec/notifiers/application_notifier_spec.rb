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

  class StubBillingNotifier < ApplicationNotifier
    category :billing

    notification_methods do
      def message = "stub-billing"
      def url     = "/stub"
    end
  end unless defined?(StubBillingNotifier)

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

  describe "dedup DSL (.dedup_bucket / .dedup_seed)" do
    # Subclasses declare their dedup window and extra key segments the same
    # way they declare `category`/`severity`; key assembly stays in ONE place
    # (the base populate_idempotency_key).
    class StubDayBucketNotifier < ApplicationNotifier
      category :account_access
      dedup_bucket :day

      notification_methods do
        def message = "stub-day"
        def url     = "/stub"
      end
    end unless defined?(StubDayBucketNotifier)

    class StubSeededNotifier < ApplicationNotifier
      category :account_access
      dedup_seed { params[:flavor] }

      notification_methods do
        def message = "stub-seeded"
        def url     = "/stub"
      end
    end unless defined?(StubSeededNotifier)

    let(:user) { create(:user) }
    let(:resource) { create(:user) }

    it "defaults to :minute granularity with no extra seed (the base behavior)" do
      expect(ApplicationNotifier.dedup_bucket_granularity).to eq :minute
      expect(StubAccountAccessNotifier.dedup_bucket_granularity).to eq :minute
      expect(StubAccountAccessNotifier.dedup_seed_block).to be_nil
    end

    it "raises ArgumentError at class-definition time for an unknown bucket granularity" do
      expect {
        Class.new(ApplicationNotifier) { dedup_bucket :fortnight }
      }.to raise_error(ArgumentError, /Invalid dedup bucket/)
    end

    it "does not leak dedup declarations between subclasses" do
      expect(StubDayBucketNotifier.dedup_bucket_granularity).to eq :day
      expect(StubAccountAccessNotifier.dedup_bucket_granularity).to eq :minute
    end

    context "with dedup_bucket :day" do
      it "deduplicates dispatches hours apart within the same day" do
        midday = Time.current.beginning_of_day + 6.hours
        first = nil
        second = nil
        travel_to(midday) do
          first = StubDayBucketNotifier.with(record: resource).deliver(user)
        end
        travel_to(midday + 6.hours) do
          second = StubDayBucketNotifier.with(record: resource).deliver(user)
        end
        expect(first).to eq :delivered
        expect(second).to eq :deduplicated
      end

      it "delivers a fresh dispatch the next day" do
        now = Time.current
        travel_to(now) do
          StubDayBucketNotifier.with(record: resource).deliver(user)
        end
        travel_to(now + 1.day) do
          expect(StubDayBucketNotifier.with(record: resource).deliver(user)).to eq :delivered
        end
      end
    end

    context "with dedup_seed" do
      it "keeps distinct seeds distinct within the same bucket" do
        freeze_time do
          vanilla   = StubSeededNotifier.with(record: resource, flavor: "vanilla").deliver(user)
          pistachio = StubSeededNotifier.with(record: resource, flavor: "pistachio").deliver(user)
          expect(vanilla).to eq :delivered
          expect(pistachio).to eq :delivered
        end
      end

      it "still deduplicates identical seeds within the same bucket" do
        freeze_time do
          first  = StubSeededNotifier.with(record: resource, flavor: "vanilla").deliver(user)
          second = StubSeededNotifier.with(record: resource, flavor: "vanilla").deliver(user)
          expect(first).to eq :delivered
          expect(second).to eq :deduplicated
        end
      end

      it "contributes the seed as a key segment between the record id and the bucket" do
        freeze_time do
          StubSeededNotifier.with(record: resource, flavor: "vanilla").deliver(user)
          event = Noticed::Event.where(type: "StubSeededNotifier").last
          expect(event.idempotency_key).to eq "StubSeededNotifier_#{resource.id}_vanilla_#{Time.current.to_i / 60}"
        end
      end
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

    it "reports the recipient's delivery decision for a channel" do
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

  describe "#deliver_email_now?" do
    # The single email gate used by every `deliver_by :email` before_enqueue
    # hook. Encapsulates the tri-state contract of recipient_pref(:email):
    # only a literal `true` means "send the instant email now" — both `false`
    # (opted out / DND) and the `:digest` sentinel (queued for the digest
    # pipeline) must abort the immediate send.
    let(:user) { create(:user) }
    let!(:prefs) { create(:user_preferences, user: user) }

    it "is true when the recipient's email preference resolves to instant delivery" do
      StubAccountAccessNotifier.with(record: user).deliver(user)
      notification = user.notifications.last
      expect(notification.deliver_email_now?).to be true
    end

    it "is false when the email preference denies (DND on for non-security)" do
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))
      StubAccountAccessNotifier.with(record: user).deliver(user)
      notification = user.notifications.last
      expect(notification.deliver_email_now?).to be false
    end

    it "is false when the preference resolves to the :digest sentinel (non-instant frequency)" do
      np = prefs.notification_preferences.deep_dup
      np["delivery_methods"]["email"]["frequency"] = "daily"
      prefs.update!(notification_preferences: np)
      StubAccountAccessNotifier.with(record: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_pref(:email)).to eq(:digest)
      expect(notification.deliver_email_now?).to be false
    end
  end

  describe "#permitted_in_app" do
    # The shared recipient gate used by every `recipients do ... end` block:
    # preload :preferences for the whole candidate set in one query, then keep
    # only users whose preferences allow the class's DECLARED category in-app.
    let(:resource) { create(:user) }
    let(:allowing_user) { create(:user) }
    let(:denying_user) { create(:user) }

    before do
      prefs = create(:user_preferences, user: denying_user)
      np = prefs.notification_preferences.deep_dup
      np["notification_types"]["account_access"] = false
      prefs.update!(notification_preferences: np)
    end

    it "keeps users whose preferences allow the category in_app and filters out those who deny" do
      event = StubAccountAccessNotifier.with(record: resource)
      expect(event.permitted_in_app([ allowing_user, denying_user ])).to eq [ allowing_user ]
    end

    it "gates on the class's declared category_name, not a hardcoded literal" do
      # denying_user disabled ONLY account_access; billing stays on. The same
      # candidate passes StubBillingNotifier's gate and fails
      # StubAccountAccessNotifier's — provable only if the category comes from
      # each class's `category` declaration rather than a re-typed string.
      expect(StubBillingNotifier.with(record: resource).permitted_in_app([ denying_user ]))
        .to eq [ denying_user ]
      expect(StubAccountAccessNotifier.with(record: resource).permitted_in_app([ denying_user ]))
        .to eq []
    end

    it "preloads :preferences once for the whole candidate set (no per-user N+1)" do
      candidates = [ allowing_user, denying_user, create(:user) ]
      event = StubAccountAccessNotifier.with(record: resource)

      query_count = count_queries_touching("user_preferences") do
        event.permitted_in_app(candidates)
      end

      expect(query_count).to eq 1
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
      expect(prefs.deliver_now?(category: "account_access", channel: "in_app")).to be true
      expect(prefs.deliver_now?(category: "workspace_activity", channel: "in_app")).to be true
      expect(prefs.deliver_now?(category: "billing", channel: "email")).to be true
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
      with_available_locale(:fr) do
        prefs.update!(locale: "fr")
        StubAccountAccessNotifier.with(record: user).deliver(user)
        notification = user.notifications.last
        expect(notification.recipient_locale).to eq :fr
      end
    end

    # Defence in depth for rows written before the inclusion validation existed
    # (or by a fork that removes a locale it once shipped). Returning the stored
    # value unchecked hands an unsupported locale to I18n.t, which raises
    # I18n::InvalidLocale — and render_safe_or_placeholder does not rescue that,
    # so the notification bell 500s.
    it "falls back to the default locale when the stored locale is unsupported" do
      prefs.update_columns(locale: "fr")
      StubAccountAccessNotifier.with(record: user).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_locale).to eq I18n.default_locale
    end

    it "renders rather than raising when the stored locale is unsupported" do
      prefs.update_columns(locale: "fr")
      StubAccountAccessNotifier.with(record: user).deliver(user)
      notification = user.notifications.last
      expect { notification.message }.not_to raise_error
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
      # All v2 surfaces broadcast_update_to (the frame ones with different
      # targets); allow them so the aria-live expectation is the only constraint.
      allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
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
      # Allow the other v2 broadcasts (avatar dot, hamburger dot, aria-live) so
      # the menu-count expectation below is the only constraint. All surfaces use
      # broadcast_update_to so the <turbo-frame> targets survive repeat refreshes.
      allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
      expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
        anything,
        hash_including(
          target: "notifications_menu_count_frame",
          partial: "shared/user_menu_notifications_row"
        )
      )

      StubAccountAccessNotifier.with(record: resource).deliver(user)
    end
  end

  describe ".notifier_class_names_for" do
    # Raw class-name variant (no ::Notification suffix). Used where the
    # parent Notifier class name is the right thing (e.g. retention
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

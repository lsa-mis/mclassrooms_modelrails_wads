require "rails_helper"

RSpec.describe NotificationPreferences do
  # New-shape JSONB matching the post-migration target. Tests against this
  # shape exclusively; the old 5×3 matrix shape is dead via the Phase 1
  # reshape migration (db/migrate/20260510212832_...).
  let(:default_jsonb) do
    {
      "notification_types" => {
        "security" => true,
        "account_access" => true,
        "workspace_activity" => true,
        "project_activity" => true,
        "billing" => true
      },
      "delivery_methods" => {
        "in_app" => { "enabled" => true },
        "email"  => { "enabled" => true, "frequency" => "instant" }
      },
      "quiet_hours" => {
        "enabled" => false,
        "start" => "22:00",
        "end" => "07:00",
        "allow_urgent" => true
      },
      "retention_days" => 90
    }
  end

  # Helper to wrap with a user that has a known timezone (for
  # quiet_hours_active? tests).
  def prefs_for(jsonb, timezone: "America/New_York")
    user = double("User", preferences: double(timezone: timezone))
    described_class.new(jsonb, user: user)
  end

  describe "#allow?" do
    subject(:prefs) { prefs_for(default_jsonb) }

    it "permits in_app for security under defaults" do
      expect(prefs.allow?(category: "security", channel: "in_app")).to be true
    end

    it "permits email for workspace_activity under defaults" do
      expect(prefs.allow?(category: "workspace_activity", channel: "email")).to be true
    end

    context "when notification_types disables a category" do
      let(:jsonb) { default_jsonb.deep_merge("notification_types" => { "workspace_activity" => false }) }
      subject(:prefs) { prefs_for(jsonb) }

      it "denies the disabled category for both channels" do
        expect(prefs.allow?(category: "workspace_activity", channel: "in_app")).to be false
        expect(prefs.allow?(category: "workspace_activity", channel: "email")).to be false
      end

      it "still permits security regardless (security floor)" do
        expect(prefs.allow?(category: "security", channel: "in_app")).to be true
      end
    end

    context "when delivery_methods disables a channel" do
      let(:jsonb) { default_jsonb.deep_merge("delivery_methods" => { "email" => { "enabled" => false } }) }
      subject(:prefs) { prefs_for(jsonb) }

      it "denies that channel even for security (channel-disabled is honored except for in_app)" do
        # Decision: a user who turns off email-channel entirely accepts that
        # security alerts won't email. Security still gets in_app though.
        expect(prefs.allow?(category: "security", channel: "email")).to be false
      end

      it "still permits security via in_app" do
        expect(prefs.allow?(category: "security", channel: "in_app")).to be true
      end
    end

    context "when email frequency is non-instant" do
      let(:jsonb) { default_jsonb.deep_merge("delivery_methods" => { "email" => { "frequency" => "daily" } }) }
      subject(:prefs) { prefs_for(jsonb) }

      it "returns :digest for email channel of non-security categories (queued, not instant)" do
        expect(prefs.allow?(category: "workspace_activity", channel: "email")).to eq(:digest)
      end

      it "still returns true (instant) for security email regardless of frequency" do
        # Security is structurally always-instant — see spec decision #7.
        expect(prefs.allow?(category: "security", channel: "email")).to be true
      end

      it "is unaffected for in_app channel (no digest concept)" do
        expect(prefs.allow?(category: "workspace_activity", channel: "in_app")).to be true
      end
    end

    context "with malformed JSONB (nil)" do
      subject(:prefs) { prefs_for(nil) }

      it "returns false for any non-security request" do
        expect(prefs.allow?(category: "workspace_activity", channel: "in_app")).to be false
      end

      it "still permits security (security bypasses missing data)" do
        expect(prefs.allow?(category: "security", channel: "in_app")).to be true
      end
    end

    it "rejects unknown category" do
      expect(prefs.allow?(category: "unicorns", channel: "in_app")).to be false
    end

    it "rejects unknown channel" do
      expect(prefs.allow?(category: "security", channel: "carrier_pigeon")).to be false
    end
  end

  describe "#quiet_hours_active?" do
    let(:tz_name) { "America/New_York" }
    let(:tz) { ActiveSupport::TimeZone[tz_name] }
    let(:enabled_jsonb) do
      default_jsonb.deep_merge("quiet_hours" => { "enabled" => true, "start" => start_t, "end" => end_t })
    end

    context "in-window same-day (start < end)" do
      let(:start_t) { "09:00" }
      let(:end_t)   { "17:00" }

      it "returns true at 13:00 local" do
        travel_to(tz.parse("2026-05-10 13:00:00")) do
          expect(prefs_for(enabled_jsonb).quiet_hours_active?).to be true
        end
      end
    end

    context "in-window overnight (after start, before midnight)" do
      let(:start_t) { "22:00" }
      let(:end_t)   { "07:00" }

      it "returns true at 23:30 local" do
        travel_to(tz.parse("2026-05-10 23:30:00")) do
          expect(prefs_for(enabled_jsonb).quiet_hours_active?).to be true
        end
      end
    end

    context "in-window overnight (after midnight, before end)" do
      let(:start_t) { "22:00" }
      let(:end_t)   { "07:00" }

      it "returns true at 06:00 local" do
        travel_to(tz.parse("2026-05-10 06:00:00")) do
          expect(prefs_for(enabled_jsonb).quiet_hours_active?).to be true
        end
      end
    end

    context "out-of-window same-day" do
      let(:start_t) { "09:00" }
      let(:end_t)   { "17:00" }

      it "returns false at 20:00 local" do
        travel_to(tz.parse("2026-05-10 20:00:00")) do
          expect(prefs_for(enabled_jsonb).quiet_hours_active?).to be false
        end
      end
    end

    context "out-of-window overnight" do
      let(:start_t) { "22:00" }
      let(:end_t)   { "07:00" }

      it "returns false at 10:00 local" do
        travel_to(tz.parse("2026-05-10 10:00:00")) do
          expect(prefs_for(enabled_jsonb).quiet_hours_active?).to be false
        end
      end
    end

    context "boundary: end is exclusive" do
      let(:start_t) { "09:00" }
      let(:end_t)   { "17:00" }

      it "returns false at exactly 17:00 local (end is exclusive)" do
        travel_to(tz.parse("2026-05-10 17:00:00")) do
          expect(prefs_for(enabled_jsonb).quiet_hours_active?).to be false
        end
      end
    end

    context "full-day window (00:00–23:59, the picker's max range)" do
      let(:start_t) { "00:00" }
      let(:end_t)   { "23:59" }

      # A user picking the picker's full range means "all day". The half-open
      # [start, end) comparison would otherwise leave a 1-minute hole at 23:59
      # (and made ~16 DND notifier specs flaky whenever CI ran in that minute).
      it "is active even during the 23:59 minute (no all-day gap)" do
        travel_to(tz.parse("2026-05-10 23:59:30")) do
          expect(prefs_for(enabled_jsonb).quiet_hours_active?).to be true
        end
      end
    end

    context "disabled" do
      it "returns false regardless of times" do
        jsonb = default_jsonb.deep_merge("quiet_hours" => { "enabled" => false, "start" => "00:00", "end" => "23:59" })
        expect(prefs_for(jsonb).quiet_hours_active?).to be false
      end
    end

    context "missing-timezone fallback" do
      it "falls back to Time.zone and does not raise" do
        jsonb = default_jsonb.deep_merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59" })
        expect { prefs_for(jsonb, timezone: nil).quiet_hours_active? }.not_to raise_error
      end
    end

    # Per-weekday filtering. `active_days` is an optional array of lowercase
    # day names ("monday"..."sunday"). Missing = legacy / all-7-days for
    # backward compat. Empty array = no days selected = quiet hours never
    # active. Day check is applied to the CURRENT day in the user's
    # timezone; overnight-window users on a day not in active_days fall
    # outside QH even if the time-of-day is inside the wrap.
    context "active_days excludes today" do
      let(:start_t) { "09:00" }
      let(:end_t)   { "17:00" }

      it "returns false when today's weekday is not in active_days" do
        # 2026-05-10 is a Sunday in America/New_York; active only Monday-Friday.
        jsonb = enabled_jsonb.deep_merge(
          "quiet_hours" => { "active_days" => %w[monday tuesday wednesday thursday friday] }
        )
        travel_to(tz.parse("2026-05-10 13:00:00")) do
          expect(prefs_for(jsonb).quiet_hours_active?).to be false
        end
      end
    end

    context "active_days includes today" do
      let(:start_t) { "09:00" }
      let(:end_t)   { "17:00" }

      it "returns true when today's weekday is in active_days and time is in window" do
        # 2026-05-11 is a Monday in America/New_York; active Monday only.
        jsonb = enabled_jsonb.deep_merge(
          "quiet_hours" => { "active_days" => %w[monday] }
        )
        travel_to(tz.parse("2026-05-11 13:00:00")) do
          expect(prefs_for(jsonb).quiet_hours_active?).to be true
        end
      end
    end

    context "active_days empty array" do
      let(:start_t) { "00:00" }
      let(:end_t)   { "23:59" }

      it "returns false (no days selected = quiet hours effectively off)" do
        jsonb = enabled_jsonb.deep_merge(
          "quiet_hours" => { "active_days" => [] }
        )
        travel_to(tz.parse("2026-05-11 13:00:00")) do
          expect(prefs_for(jsonb).quiet_hours_active?).to be false
        end
      end
    end

    context "active_days missing (legacy data backward compat)" do
      let(:start_t) { "09:00" }
      let(:end_t)   { "17:00" }

      it "applies window every day when active_days key is absent" do
        # No active_days key in jsonb — legacy data shape from pre-PR rows.
        # Should behave as if all 7 days are active.
        jsonb = enabled_jsonb # has no active_days key
        travel_to(tz.parse("2026-05-11 13:00:00")) do
          expect(prefs_for(jsonb).quiet_hours_active?).to be true
        end
      end
    end

    context "active_days with overnight window" do
      let(:start_t) { "22:00" }
      let(:end_t)   { "07:00" }
      let(:active_only_sunday) do
        enabled_jsonb.deep_merge("quiet_hours" => { "active_days" => %w[sunday] })
      end

      it "is active at 23:30 Sunday (day matches, time in window)" do
        travel_to(tz.parse("2026-05-10 23:30:00")) do
          expect(prefs_for(active_only_sunday).quiet_hours_active?).to be true
        end
      end

      it "is NOT active at 06:00 Monday (time still in overnight wrap, but Monday not in active_days)" do
        # Documents the chosen semantic: per-weekday check is applied to
        # the CURRENT day, not the day the window started. Users who want
        # "Sunday-night sleep through Monday morning" must include Monday
        # in active_days.
        travel_to(tz.parse("2026-05-11 06:00:00")) do
          expect(prefs_for(active_only_sunday).quiet_hours_active?).to be false
        end
      end
    end
  end

  describe "#allow? with quiet hours active" do
    let(:tz_name) { "America/New_York" }
    let(:tz) { ActiveSupport::TimeZone[tz_name] }
    let(:always_on) { { "enabled" => true, "start" => "00:00", "end" => "23:59" } }

    it "denies non-security categories when quiet hours are active" do
      jsonb = default_jsonb.deep_merge("quiet_hours" => always_on)
      travel_to(tz.parse("2026-05-10 12:00:00")) do
        expect(prefs_for(jsonb).allow?(category: "workspace_activity", channel: "email")).to be false
      end
    end

    it "still permits security category when quiet hours are active (security bypasses)" do
      jsonb = default_jsonb.deep_merge("quiet_hours" => always_on)
      travel_to(tz.parse("2026-05-10 12:00:00")) do
        expect(prefs_for(jsonb).allow?(category: "security", channel: "email")).to be true
      end
    end
  end

  describe "#email_frequency" do
    it "returns 'instant' under defaults" do
      expect(prefs_for(default_jsonb).email_frequency).to eq("instant")
    end

    it "returns 'daily' when configured" do
      jsonb = default_jsonb.deep_merge("delivery_methods" => { "email" => { "frequency" => "daily" } })
      expect(prefs_for(jsonb).email_frequency).to eq("daily")
    end

    it "returns 'instant' as fallback when key is absent" do
      expect(prefs_for({}).email_frequency).to eq("instant")
    end
  end

  describe "#digest_enabled?" do
    it "is false under defaults (email frequency = instant)" do
      expect(prefs_for(default_jsonb).digest_enabled?).to be false
    end

    it "is true when email frequency is daily" do
      jsonb = default_jsonb.deep_merge("delivery_methods" => { "email" => { "frequency" => "daily" } })
      expect(prefs_for(jsonb).digest_enabled?).to be true
    end

    it "is false when email channel is disabled (even if frequency was daily)" do
      jsonb = default_jsonb.deep_merge("delivery_methods" => { "email" => { "enabled" => false, "frequency" => "daily" } })
      expect(prefs_for(jsonb).digest_enabled?).to be false
    end
  end

  describe "#digest_cadence" do
    it "returns 'daily' when frequency is daily" do
      jsonb = default_jsonb.deep_merge("delivery_methods" => { "email" => { "frequency" => "daily" } })
      expect(prefs_for(jsonb).digest_cadence).to eq("daily")
    end

    it "returns 'weekly' when frequency is weekly" do
      jsonb = default_jsonb.deep_merge("delivery_methods" => { "email" => { "frequency" => "weekly" } })
      expect(prefs_for(jsonb).digest_cadence).to eq("weekly")
    end

    it "returns 'daily' as fallback when frequency is instant or absent" do
      expect(prefs_for(default_jsonb).digest_cadence).to eq("daily")
    end
  end

  describe "#retention_days" do
    it "returns the configured value" do
      expect(prefs_for(default_jsonb).retention_days).to eq 90
    end

    it "returns nil for never (key explicitly set to nil)" do
      expect(prefs_for(default_jsonb.merge("retention_days" => nil)).retention_days).to be_nil
    end
  end

  describe "#next_due_at_in" do
    let(:tz) { ActiveSupport::TimeZone["America/New_York"] }

    it "returns the next 8am-local for daily cadence" do
      jsonb = default_jsonb.deep_merge("delivery_methods" => { "email" => { "frequency" => "daily" } })
      travel_to(tz.parse("2026-04-30 14:00:00")) do
        expect(prefs_for(jsonb).next_due_at_in(tz)).to eq tz.parse("2026-05-01 08:00:00")
      end
    end

    it "returns 7 days out for weekly cadence" do
      jsonb = default_jsonb.deep_merge("delivery_methods" => { "email" => { "frequency" => "weekly" } })
      travel_to(tz.parse("2026-04-30 14:00:00")) do
        expect(prefs_for(jsonb).next_due_at_in(tz)).to eq tz.parse("2026-05-07 08:00:00")
      end
    end
  end

  describe "constants" do
    it "lists 5 categories (unchanged)" do
      expect(described_class::CATEGORIES).to eq %w[security account_access workspace_activity project_activity billing]
    end

    it "lists 2 channels — digest folded into email" do
      expect(described_class::CHANNELS).to eq %w[in_app email]
    end

    it "lists 3 email frequencies" do
      expect(described_class::EMAIL_FREQUENCIES).to eq %w[instant daily weekly]
    end

    it "enforces a 1-year floor for security retention" do
      expect(described_class::RETENTION_FLOORS["security"]).to eq 365.days
    end

    it "freezes all collection constants" do
      expect(described_class::CATEGORIES).to be_frozen
      expect(described_class::CHANNELS).to be_frozen
      expect(described_class::EMAIL_FREQUENCIES).to be_frozen
      expect(described_class::RETENTION_FLOORS).to be_frozen
    end
  end

  describe ".security_notifier_types" do
    it "returns class names of every Notifier with category :security" do
      _ = PasswordChangedNotifier
      result = described_class.security_notifier_types
      expect(result).to include("PasswordChangedNotifier")
    end

    it "excludes non-security Notifiers" do
      _ = WorkspaceInvitationReceivedNotifier
      result = described_class.security_notifier_types
      expect(result).not_to include("WorkspaceInvitationReceivedNotifier")
    end
  end

  # do_not_disturb? is kept as a back-compat alias for quiet_hours_active?
  # so existing callers (notably the bell button tooltip) continue working.
  # Semantic shift documented in the value object.
  describe "#do_not_disturb? (back-compat alias)" do
    let(:tz) { ActiveSupport::TimeZone["America/New_York"] }

    it "delegates to quiet_hours_active?" do
      jsonb = default_jsonb.deep_merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59" })
      travel_to(tz.parse("2026-05-10 12:00:00")) do
        expect(prefs_for(jsonb).do_not_disturb?).to be true
      end
    end

    it "is false when quiet hours are disabled" do
      expect(prefs_for(default_jsonb).do_not_disturb?).to be false
    end
  end

  # Validation + coerce + deep_merge moved here from
  # Settings::NotificationPreferencesController#apply_changes! per panel
  # review should-fix #7 (DHH + Chris Oliver + Dave Thomas). The controller
  # was carrying schema validation that belongs on the value object —
  # half-Result pattern (`:rejected` sentinel) made return semantics fuzzy
  # and coupled the controller to JSONB shape decisions.
  describe "#merge (validation + coercion of partial changes)" do
    it "returns a new value object with the changes deep-merged in" do
      prefs = prefs_for(default_jsonb)
      merged = prefs.merge("quiet_hours" => { "enabled" => "true" })

      expect(merged).to be_a(described_class)
      expect(merged.to_h.dig("quiet_hours", "enabled")).to eq(true)
      # Sibling keys preserved (deep_merge, not overwrite).
      expect(merged.to_h.dig("quiet_hours", "start")).to eq("22:00")
    end

    it "leaves the receiver untouched (immutability — no half-applied state)" do
      prefs = prefs_for(default_jsonb)
      original = prefs.to_h

      prefs.merge("quiet_hours" => { "enabled" => "true" })

      expect(prefs.to_h).to eq(original)
    end

    it "returns self when changes are blank" do
      prefs = prefs_for(default_jsonb)
      expect(prefs.merge({})).to equal(prefs)
    end

    it "coerces 'true'/'false' strings to booleans before merging" do
      merged = prefs_for(default_jsonb).merge(
        "delivery_methods" => { "email" => { "enabled" => "false" } }
      )
      expect(merged.to_h.dig("delivery_methods", "email", "enabled")).to eq(false)
    end

    it "normalizes retention_days='never' to nil" do
      merged = prefs_for(default_jsonb).merge("retention_days" => "never")
      expect(merged.to_h["retention_days"]).to be_nil
    end

    it "coerces retention_days integer-strings to Integer" do
      merged = prefs_for(default_jsonb).merge("retention_days" => "60")
      expect(merged.to_h["retention_days"]).to eq(60)
    end

    it "raises InvalidChange for retention_days outside the allowed list" do
      expect {
        prefs_for(default_jsonb).merge("retention_days" => "999")
      }.to raise_error(NotificationPreferences::InvalidChange)
    end

    it "raises InvalidChange for an unknown notification_types category" do
      expect {
        prefs_for(default_jsonb).merge("notification_types" => { "moon_phase" => true })
      }.to raise_error(NotificationPreferences::InvalidChange)
    end

    it "raises InvalidChange for an unknown email.frequency value" do
      expect {
        prefs_for(default_jsonb).merge("delivery_methods" => { "email" => { "frequency" => "fortnightly" } })
      }.to raise_error(NotificationPreferences::InvalidChange)
    end

    it "raises InvalidChange for an invalid quiet_hours.start format" do
      expect {
        prefs_for(default_jsonb).merge("quiet_hours" => { "start" => "25:00" })
      }.to raise_error(NotificationPreferences::InvalidChange)
    end

    it "strips Rails' empty-array sentinel from active_days" do
      merged = prefs_for(default_jsonb).merge(
        "quiet_hours" => { "active_days" => [ "", "monday", "wednesday" ] }
      )
      expect(merged.to_h.dig("quiet_hours", "active_days")).to eq([ "monday", "wednesday" ])
    end

    it "raises InvalidChange when active_days contains an unknown day" do
      expect {
        prefs_for(default_jsonb).merge("quiet_hours" => { "active_days" => [ "yesterday" ] })
      }.to raise_error(NotificationPreferences::InvalidChange)
    end
  end

  describe "#digest_changed_by?" do
    let(:prefs) { prefs_for(default_jsonb) }

    it "is true when changes include delivery_methods.email.frequency" do
      expect(prefs.digest_changed_by?("delivery_methods" => { "email" => { "frequency" => "daily" } })).to eq(true)
    end

    it "is false when changes do not touch email frequency" do
      expect(prefs.digest_changed_by?("quiet_hours" => { "enabled" => "true" })).to eq(false)
    end

    it "is false for empty changes" do
      expect(prefs.digest_changed_by?({})).to eq(false)
    end
  end
end

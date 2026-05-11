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
end

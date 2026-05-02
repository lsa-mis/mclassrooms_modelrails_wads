require "rails_helper"

RSpec.describe NotificationPreferences do
  let(:default_jsonb) do
    {
      "do_not_disturb" => false,
      "digest" => { "enabled" => true, "cadence" => "daily", "hour_local" => 8 },
      "categories" => {
        "security"           => { "in_app" => true, "email" => true, "digest" => false },
        "account_access"     => { "in_app" => true, "email" => true, "digest" => false },
        "workspace_activity" => { "in_app" => true, "email" => false, "digest" => true },
        "project_activity"   => { "in_app" => true, "email" => false, "digest" => true },
        "billing"            => { "in_app" => true, "email" => true, "digest" => false }
      },
      "retention_days" => 90
    }
  end

  describe "#allow?" do
    subject(:prefs) { described_class.new(default_jsonb) }

    it "permits in_app for security under defaults" do
      expect(prefs.allow?(category: "security", channel: "in_app")).to be true
    end

    it "denies digest for billing under defaults" do
      expect(prefs.allow?(category: "billing", channel: "digest")).to be false
    end

    context "when do_not_disturb is true" do
      let(:dnd) { default_jsonb.merge("do_not_disturb" => true) }
      subject(:prefs) { described_class.new(dnd) }

      it "still permits security category" do
        expect(prefs.allow?(category: "security", channel: "email")).to be true
      end

      it "suppresses non-security categories" do
        expect(prefs.allow?(category: "workspace_activity", channel: "in_app")).to be false
        expect(prefs.allow?(category: "billing", channel: "email")).to be false
      end
    end

    context "with missing category in JSONB (forward compat)" do
      let(:partial) { default_jsonb.tap { |h| h["categories"].delete("billing") } }
      subject(:prefs) { described_class.new(partial) }

      it "returns false rather than raising" do
        expect(prefs.allow?(category: "billing", channel: "email")).to be false
      end
    end

    context "with malformed JSONB (nil)" do
      subject(:prefs) { described_class.new(nil) }

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

    it "rejects nil category" do
      expect(prefs.allow?(category: nil, channel: "in_app")).to be false
    end

    it "rejects empty-string category" do
      expect(prefs.allow?(category: "", channel: "in_app")).to be false
    end
  end

  describe "#do_not_disturb?" do
    it "is false by default" do
      expect(described_class.new(default_jsonb).do_not_disturb?).to be false
    end

    it "respects nil JSONB" do
      expect(described_class.new(nil).do_not_disturb?).to be false
    end
  end

  describe "#digest_enabled?" do
    it "is true by default" do
      expect(described_class.new(default_jsonb).digest_enabled?).to be true
    end

    it "is true when key absent (default-on)" do
      expect(described_class.new({}).digest_enabled?).to be true
    end

    it "is false when explicitly disabled" do
      jsonb = default_jsonb.deep_merge("digest" => { "enabled" => false })
      expect(described_class.new(jsonb).digest_enabled?).to be false
    end
  end

  describe "#retention_days" do
    it "returns the configured value" do
      expect(described_class.new(default_jsonb).retention_days).to eq 90
    end

    it "returns nil for never (key explicitly set to nil)" do
      expect(described_class.new(default_jsonb.merge("retention_days" => nil)).retention_days).to be_nil
    end

    it "returns nil when key is absent from the jsonb (corrupt or pre-migration row)" do
      jsonb = default_jsonb.except("retention_days")
      expect(described_class.new(jsonb).retention_days).to be_nil
    end
  end

  describe "#next_due_at_in" do
    let(:tz) { ActiveSupport::TimeZone["America/New_York"] }

    it "returns the next 8am-local for daily cadence" do
      travel_to(tz.parse("2026-04-30 14:00:00")) do
        expect(described_class.new(default_jsonb).next_due_at_in(tz)).to eq tz.parse("2026-05-01 08:00:00")
      end
    end

    it "advances to tomorrow when frozen exactly at 08:00:00 (daily cadence)" do
      # Edge case: at exactly 8am-local, today's slot has just passed; next due is tomorrow.
      travel_to(tz.parse("2026-04-30 08:00:00")) do
        expect(described_class.new(default_jsonb).next_due_at_in(tz)).to eq tz.parse("2026-05-01 08:00:00")
      end
    end

    it "returns 7 days out for weekly cadence" do
      jsonb = default_jsonb.deep_merge("digest" => { "cadence" => "weekly" })
      travel_to(tz.parse("2026-04-30 14:00:00")) do
        expect(described_class.new(jsonb).next_due_at_in(tz)).to eq tz.parse("2026-05-07 08:00:00")
      end
    end

    it "handles DST transition correctly across spring-forward (weekly cadence)" do
      # March 8, 2026 is US spring-forward Sunday. Test that ActiveSupport's
      # Duration arithmetic does the right thing across the boundary.
      jsonb = default_jsonb.deep_merge("digest" => { "cadence" => "weekly" })
      travel_to(tz.parse("2026-03-01 14:00:00")) do
        expect(described_class.new(jsonb).next_due_at_in(tz)).to eq tz.parse("2026-03-08 08:00:00")
      end
    end

    it "handles DST transition correctly across fall-back (weekly cadence)" do
      # November 1, 2026 is US fall-back Sunday. Test that ActiveSupport's
      # Duration arithmetic does the right thing across the boundary.
      jsonb = default_jsonb.deep_merge("digest" => { "cadence" => "weekly" })
      travel_to(tz.parse("2026-10-25 14:00:00")) do
        expect(described_class.new(jsonb).next_due_at_in(tz)).to eq tz.parse("2026-11-01 08:00:00")
      end
    end

    it "for weekly cadence at exactly 08:00:00, returns 7 days out (today's slot just passed, next 8am + 6 days)" do
      # At exactly 8am the `<= now` guard advances to tomorrow (May 1),
      # then +6 days for weekly = May 7. Not May 8 — the +1-day is the
      # next-daily-slot, and weekly adds 6 on top of that.
      jsonb = default_jsonb.deep_merge("digest" => { "cadence" => "weekly" })
      travel_to(tz.parse("2026-04-30 08:00:00")) do
        expect(described_class.new(jsonb).next_due_at_in(tz)).to eq tz.parse("2026-05-07 08:00:00")
      end
    end
  end

  describe "constants" do
    it "lists 5 categories" do
      expect(described_class::CATEGORIES).to eq %w[security account_access workspace_activity project_activity billing]
    end

    it "lists 3 channels" do
      expect(described_class::CHANNELS).to eq %w[in_app email digest]
    end

    it "names exactly the digest-eligible categories" do
      expect(described_class::DIGEST_ELIGIBLE_CATEGORIES).to eq %w[workspace_activity project_activity]
    end

    it "enforces a 1-year floor for security retention (string-keyed for consistency with category strings)" do
      expect(described_class::RETENTION_FLOORS["security"]).to eq 365.days
    end

    it "freezes all collection constants" do
      expect(described_class::CATEGORIES).to be_frozen
      expect(described_class::CHANNELS).to be_frozen
      expect(described_class::DIGEST_ELIGIBLE_CATEGORIES).to be_frozen
      expect(described_class::RETENTION_FLOORS).to be_frozen
    end
  end

  describe ".security_notifier_types" do
    it "returns class names of every Notifier with category :security" do
      # Reference the security-category Notifier explicitly so autoload runs.
      _ = PasswordChangedNotifier
      result = described_class.security_notifier_types
      expect(result).to include("PasswordChangedNotifier")
    end

    it "excludes non-security Notifiers" do
      _ = WorkspaceInvitationReceivedNotifier  # category :account_access
      result = described_class.security_notifier_types
      expect(result).not_to include("WorkspaceInvitationReceivedNotifier")
    end
  end
end

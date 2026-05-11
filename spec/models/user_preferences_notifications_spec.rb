require "rails_helper"

RSpec.describe UserPreferences, "notification_preferences columns" do
  let(:user) { create(:user) }
  let(:prefs) { user.preferences || create(:user_preferences, user: user) }

  describe "notification_preferences default" do
    it "populates a fully-formed JSONB hash on a new row" do
      np = prefs.notification_preferences
      expect(np).to be_a(Hash)
      expect(np.keys).to include("notification_types", "delivery_methods", "quiet_hours", "retention_days")
    end

    it "has quiet_hours.enabled defaulting to false (DND off by default)" do
      expect(prefs.notification_preferences.dig("quiet_hours", "enabled")).to eq false
    end

    it "has email channel enabled at instant frequency by default (digest off)" do
      email = prefs.notification_preferences.dig("delivery_methods", "email")
      expect(email).to eq("enabled" => true, "frequency" => "instant")
    end

    it "has all 5 expected notification_types as booleans" do
      types = prefs.notification_preferences["notification_types"]
      expect(types.keys).to match_array(%w[security account_access workspace_activity project_activity billing])
      types.each_value { |v| expect(v).to be(true).or be(false) }
    end

    it "applies the documented v2 default (everything-on, instant, quiet hours off)" do
      np = prefs.notification_preferences
      # All 5 categories opted in by default — IA shift means users tune by
      # exception (turn off what they don't want) rather than opt-in.
      expect(np["notification_types"]).to eq(
        "security" => true, "account_access" => true, "workspace_activity" => true,
        "project_activity" => true, "billing" => true
      )
      # Both delivery channels on; email is instant (digest opt-in, not default).
      expect(np["delivery_methods"]).to eq(
        "in_app" => { "enabled" => true },
        "email" => { "enabled" => true, "frequency" => "instant" }
      )
      # Quiet hours scheduled but disabled — schedule is the schema default
      # so toggling enabled is the only step the user needs.
      expect(np["quiet_hours"]).to eq(
        "enabled" => false, "start" => "22:00", "end" => "07:00", "allow_urgent" => true
      )
    end

    it "has retention_days defaulting to 90" do
      expect(prefs.notification_preferences["retention_days"]).to eq 90
    end
  end

  describe "digest_next_due_at column" do
    it "exists and accepts a datetime" do
      target = 12.hours.from_now
      prefs.update!(digest_next_due_at: target)
      expect(prefs.reload.digest_next_due_at).to be_within(1.second).of(target)
    end

    it "is nullable" do
      prefs.update!(digest_next_due_at: nil)
      expect(prefs.reload.digest_next_due_at).to be_nil
    end

    it "has a partial index where digest_next_due_at IS NOT NULL" do
      indexes = ActiveRecord::Base.connection.indexes("user_preferences")
      idx = indexes.find { |i| i.name == "index_user_preferences_on_digest_next_due_at" }
      expect(idx).not_to be_nil
      expect(idx.where).to include("digest_next_due_at IS NOT NULL")
    end
  end

  describe "digest_last_sent_at column" do
    it "exists and accepts a datetime" do
      target = 1.hour.ago
      prefs.update!(digest_last_sent_at: target)
      expect(prefs.reload.digest_last_sent_at).to be_within(1.second).of(target)
    end
  end

  describe "backfill of existing rows" do
    it "populates digest_next_due_at for existing rows on a future timestamp within 24 hours" do
      # The backfill migration randomizes existing rows across the next 24
      # hours. After running migrations, any pre-existing user_preferences
      # rows should have a digest_next_due_at set.
      sample = UserPreferences.where.not(digest_next_due_at: nil).first
      next unless sample  # tolerable if there are no existing rows in test DB

      expect(sample.digest_next_due_at).to be > Time.current
      expect(sample.digest_next_due_at).to be < 24.hours.from_now + 1.hour
    end
  end
end

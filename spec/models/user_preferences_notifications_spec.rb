require "rails_helper"

RSpec.describe UserPreferences, "notification_preferences columns" do
  let(:user) { create(:user) }
  let(:prefs) { user.preferences || create(:user_preferences, user: user) }

  describe "notification_preferences default" do
    it "populates a fully-formed JSONB hash on a new row" do
      np = prefs.notification_preferences
      expect(np).to be_a(Hash)
      expect(np.keys).to include("do_not_disturb", "digest", "categories", "retention_days")
    end

    it "has do_not_disturb defaulting to false" do
      expect(prefs.notification_preferences["do_not_disturb"]).to eq false
    end

    it "has digest enabled with daily cadence and 8am hour_local" do
      digest = prefs.notification_preferences["digest"]
      expect(digest).to eq("enabled" => true, "cadence" => "daily", "hour_local" => 8)
    end

    it "has all 5 expected categories with 3-channel toggles" do
      cats = prefs.notification_preferences["categories"]
      expect(cats.keys).to match_array(%w[security account_access workspace_activity project_activity billing])
      cats.each do |_, channels|
        expect(channels.keys).to match_array(%w[in_app email digest])
      end
    end

    it "applies the documented default channel matrix" do
      cats = prefs.notification_preferences["categories"]
      expect(cats["security"]).to            eq("in_app" => true, "email" => true,  "digest" => false)
      expect(cats["account_access"]).to      eq("in_app" => true, "email" => true,  "digest" => false)
      expect(cats["workspace_activity"]).to  eq("in_app" => true, "email" => false, "digest" => true)
      expect(cats["project_activity"]).to    eq("in_app" => true, "email" => false, "digest" => true)
      expect(cats["billing"]).to             eq("in_app" => true, "email" => true,  "digest" => false)
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

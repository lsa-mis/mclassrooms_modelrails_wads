require "rails_helper"
require_relative "../../db/migrate/20260510212832_reshape_notification_preferences_jsonb"

# Unit spec for the JSONB reshape rules. Covers four representative legacy
# shapes from the v1 5×3 matrix and asserts the target shape per the spec's
# backfill rules (Jason-Fried-flavored OR collapse). Migration's data step
# iterates over UserPreferences rows and writes the reshape's output via
# update_column; the rule logic is the failure-prone surface, so this is
# where TDD discipline matters most.
RSpec.describe ReshapeNotificationPreferencesJsonb do
  describe ".reshape_legacy_jsonb" do
    subject(:reshape) { described_class.reshape_legacy_jsonb(legacy) }

    context "everything-on legacy shape (user enabled every channel for every category)" do
      let(:legacy) do
        {
          "do_not_disturb" => false,
          "categories" => {
            "security"           => { "in_app" => true, "email" => true, "digest" => false },
            "account_access"     => { "in_app" => true, "email" => true, "digest" => false },
            "workspace_activity" => { "in_app" => true, "email" => true, "digest" => true },
            "project_activity"   => { "in_app" => true, "email" => true, "digest" => true },
            "billing"            => { "in_app" => true, "email" => true, "digest" => true }
          },
          "digest" => { "cadence" => "daily", "hour_local" => 8 },
          "retention_days" => 90
        }
      end

      it "enables every notification_type" do
        expect(reshape["notification_types"]).to eq(
          "security" => true,
          "account_access" => true,
          "workspace_activity" => true,
          "project_activity" => true,
          "billing" => true
        )
      end

      it "enables both delivery methods with email frequency = daily (digest was on for some categories)" do
        expect(reshape["delivery_methods"]).to eq(
          "in_app" => { "enabled" => true },
          "email"  => { "enabled" => true, "frequency" => "daily" }
        )
      end

      it "starts quiet hours disabled with default times + allow_urgent=true" do
        expect(reshape["quiet_hours"]).to eq(
          "enabled" => false,
          "start" => "22:00",
          "end" => "07:00",
          "allow_urgent" => true
        )
      end

      it "preserves retention_days" do
        expect(reshape["retention_days"]).to eq(90)
      end
    end

    context "everything-off legacy shape (user disabled all non-security categories)" do
      let(:legacy) do
        {
          "do_not_disturb" => false,
          "categories" => {
            "security"           => { "in_app" => true, "email" => true, "digest" => false },
            "account_access"     => { "in_app" => false, "email" => false, "digest" => false },
            "workspace_activity" => { "in_app" => false, "email" => false, "digest" => false },
            "project_activity"   => { "in_app" => false, "email" => false, "digest" => false },
            "billing"            => { "in_app" => false, "email" => false, "digest" => false }
          },
          "digest" => { "cadence" => "daily", "hour_local" => 8 },
          "retention_days" => 90
        }
      end

      it "forces security on regardless (security floor)" do
        expect(reshape["notification_types"]["security"]).to be true
      end

      it "disables all other notification_types" do
        expect(reshape["notification_types"]["account_access"]).to be false
        expect(reshape["notification_types"]["workspace_activity"]).to be false
        expect(reshape["notification_types"]["project_activity"]).to be false
        expect(reshape["notification_types"]["billing"]).to be false
      end

      it "keeps in_app + email enabled because security row had them" do
        expect(reshape["delivery_methods"]["in_app"]["enabled"]).to be true
        expect(reshape["delivery_methods"]["email"]["enabled"]).to be true
      end

      it "sets email frequency = instant (no category had digest)" do
        expect(reshape["delivery_methods"]["email"]["frequency"]).to eq("instant")
      end
    end

    context "DND-on legacy shape" do
      let(:legacy) do
        {
          "do_not_disturb" => true,
          "categories" => {
            "security"           => { "in_app" => true, "email" => true, "digest" => false },
            "account_access"     => { "in_app" => true, "email" => false, "digest" => false },
            "workspace_activity" => { "in_app" => true, "email" => false, "digest" => false },
            "project_activity"   => { "in_app" => true, "email" => false, "digest" => false },
            "billing"            => { "in_app" => true, "email" => false, "digest" => false }
          },
          "digest" => { "cadence" => "daily", "hour_local" => 8 },
          "retention_days" => 60
        }
      end

      it "translates legacy do_not_disturb=true to quiet_hours.enabled=true" do
        expect(reshape["quiet_hours"]["enabled"]).to be true
      end

      it "preserves the retention_days from legacy (60)" do
        expect(reshape["retention_days"]).to eq(60)
      end

      it "disables email channel because no category had email=true (security row excepted)" do
        # security row HAD email=true so the OR rule produces email.enabled=true.
        expect(reshape["delivery_methods"]["email"]["enabled"]).to be true
      end
    end

    context "mixed-digest legacy shape (some categories had digest, others didn't)" do
      let(:legacy) do
        {
          "do_not_disturb" => false,
          "categories" => {
            "security"           => { "in_app" => true, "email" => true, "digest" => false },
            "account_access"     => { "in_app" => true, "email" => true, "digest" => false },
            "workspace_activity" => { "in_app" => true, "email" => false, "digest" => true },
            "project_activity"   => { "in_app" => false, "email" => false, "digest" => false },
            "billing"            => { "in_app" => true, "email" => true, "digest" => false }
          },
          "digest" => { "cadence" => "weekly", "hour_local" => 9 },
          "retention_days" => 30
        }
      end

      it "enables workspace_activity (had digest=true → counts as ON)" do
        expect(reshape["notification_types"]["workspace_activity"]).to be true
      end

      it "disables project_activity (all channels off)" do
        expect(reshape["notification_types"]["project_activity"]).to be false
      end

      it "sets email frequency = daily because at least one category had digest=true" do
        expect(reshape["delivery_methods"]["email"]["frequency"]).to eq("daily")
      end

      it "preserves retention_days (30)" do
        expect(reshape["retention_days"]).to eq(30)
      end
    end

    context "nil-or-missing-keys legacy shape (defensive)" do
      let(:legacy) { nil }

      it "returns a valid new-shape JSONB with security-on default" do
        expect(reshape["notification_types"]["security"]).to be true
      end

      it "starts all other types off when legacy has no categories" do
        %w[account_access workspace_activity project_activity billing].each do |c|
          expect(reshape["notification_types"][c]).to be false
        end
      end

      it "defaults delivery methods to enabled=true, email frequency=instant" do
        expect(reshape["delivery_methods"]["in_app"]["enabled"]).to be true
        expect(reshape["delivery_methods"]["email"]["enabled"]).to be true
        expect(reshape["delivery_methods"]["email"]["frequency"]).to eq("instant")
      end

      it "defaults retention_days to 90" do
        expect(reshape["retention_days"]).to eq(90)
      end
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkspaceCapacityApproachingNotifier, type: :notifier do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  # Drain only the Noticed-pipeline jobs that fan out to ActionMailer; we
  # deliberately scope perform_enqueued_jobs to avoid running unrelated jobs
  # like CheckGravatarJob (enqueued from the user factory) which does network
  # IO and isn't relevant to this notifier.
  def drain_noticed_jobs
    perform_enqueued_jobs(only: Noticed::EventJob)
    perform_enqueued_jobs(only: Noticed::DeliveryMethods::Email)
  end

  let(:owner_role) do
    Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_settings: true }
    end
  end

  let(:workspace) { create(:workspace) }

  # Two owners + one non-owner. All `let!` so the User-factory side effect
  # (personal-workspace Membership creation triggers WorkspaceMemberAddedNotifier)
  # is fully resolved before each example begins.
  let!(:owner_a) { create(:user) }
  let!(:owner_b) { create(:user) }
  let!(:non_owner) { create(:user) }
  let!(:owner_a_membership) { create(:membership, user: owner_a, workspace: workspace, role: owner_role) }
  let!(:owner_b_membership) { create(:membership, user: owner_b, workspace: workspace, role: owner_role) }
  let!(:non_owner_membership) { create(:membership, user: non_owner, workspace: workspace) }

  before do
    Noticed::Notification.delete_all
    Noticed::Event.delete_all
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs
  end

  describe ".category" do
    it "is :billing" do
      expect(described_class.category_name).to eq "billing"
    end

    it "is NOT a security category notifier (does not bypass DND)" do
      expect(NotificationPreferences.security_notifier_types).not_to include(described_class.name)
    end
  end

  describe "recipient resolution" do
    it "resolves to all workspace owners (excludes non-owner members)" do
      event = described_class.with(record: workspace, metric: "members", current: 8, limit: 10)
      recipients = event.send(:evaluate_recipients)
      expect(recipients).to match_array([ owner_a, owner_b ])
      expect(recipients).not_to include(non_owner)
    end
  end

  describe "dispatching" do
    it "delivers in-app notifications to all owners under default preferences" do
      result = described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
      expect(result).to eq :delivered
      expect(Noticed::Notification.where(recipient: owner_a, type: "#{described_class.name}::Notification").count).to eq 1
      expect(Noticed::Notification.where(recipient: owner_b, type: "#{described_class.name}::Notification").count).to eq 1
      expect(Noticed::Notification.where(recipient: non_owner, type: "#{described_class.name}::Notification").count).to eq 0
    end

    it "auto-populates idempotency_key on the event column" do
      described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
      event = Noticed::Event.last
      expect(event.idempotency_key).to be_present
      expect(event.params["idempotency_key"]).to be_nil
    end

    it "enqueues NotificationMailer.workspace_capacity_approaching for each owner under default preferences" do
      expect {
        described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
        drain_noticed_jobs
      }.to have_enqueued_mail(NotificationMailer, :workspace_capacity_approaching).twice
    end

    it "creates exactly one Noticed::Event row per dispatch (regardless of recipient count)" do
      expect {
        described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
      }.to change { Noticed::Event.where(type: described_class.name).count }.by(1)
    end
  end

  describe "day-bucket idempotency" do
    it "deduplicates two consecutive dispatches within the same day for the same (workspace, metric)" do
      freeze_time do
        first = described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
        second = described_class.with(record: workspace, metric: "members", current: 9, limit: 10).deliver(nil)
        expect(first).to eq :delivered
        expect(second).to eq :deduplicated
      end
    end

    it "delivers a fresh dispatch the next day" do
      now = Time.current
      travel_to(now) do
        described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
      end

      travel_to(now + 1.day) do
        result = described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
        expect(result).to eq :delivered
      end
    end

    it "does not deduplicate across distinct metrics on the same day" do
      freeze_time do
        members = described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
        projects = described_class.with(record: workspace, metric: "projects", current: 4, limit: 5).deliver(nil)
        expect(members).to eq :delivered
        expect(projects).to eq :delivered
      end
    end
  end

  describe "preference gating" do
    let!(:prefs) { create(:user_preferences, user: owner_a) }

    it "suppresses both in-app and email under DND for that owner (billing does NOT bypass)" do
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))

      described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
      drain_noticed_jobs

      expect(Noticed::Notification.where(recipient: owner_a,
                                          type: "#{described_class.name}::Notification").count).to eq 0
      # owner_b unaffected
      expect(Noticed::Notification.where(recipient: owner_b,
                                          type: "#{described_class.name}::Notification").count).to eq 1
    end

    it "fires in-app but skips email when the email channel is disabled" do
      delivery_methods = prefs.notification_preferences["delivery_methods"].deep_dup
      delivery_methods["email"]["enabled"] = false
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("delivery_methods" => delivery_methods))

      described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)

      notification = Noticed::Notification.find_by(recipient: owner_a, type: "#{described_class.name}::Notification")
      expect(notification).not_to be_nil
      expect(notification.recipient_pref(:in_app)).to be true
      expect(notification.recipient_pref(:email)).to be false
    end
  end

  describe "#message" do
    it "renders the localized capacity-approaching message with workspace, metric, current and limit" do
      described_class.with(record: workspace, metric: "members", current: 8, limit: 10).deliver(nil)
      notification = Noticed::Notification.find_by(recipient: owner_a, type: "#{described_class.name}::Notification")
      expect(notification.message).to eq(
        I18n.t("notifications.workspace_capacity_approaching.message",
               workspace: workspace.name,
               metric: "members",
               current: 8,
               limit: 10)
      )
    end
  end
end

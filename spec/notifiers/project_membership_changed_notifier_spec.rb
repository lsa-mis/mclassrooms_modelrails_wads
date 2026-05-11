# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectMembershipChangedNotifier, type: :notifier do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  let(:workspace) { create(:workspace) }
  let(:user) { create(:user) }
  let!(:membership) { create(:membership, user: user, workspace: workspace) }
  let(:project) { create(:project, workspace: workspace) }
  let(:project_membership) { ProjectMembership.create!(project: project, user: user, role: "editor") }

  describe ".category" do
    it "is :project_activity" do
      expect(described_class.category_name).to eq "project_activity"
    end
  end

  describe "dispatching" do
    it "delivers to the project membership's user and creates a Noticed::Notification row" do
      pm = ProjectMembership.new(project: project, user: user, role: "editor")
      pm.save(validate: true)
      # Re-using the same record + same minute would dedup; bypass that for the
      # explicit-deliver assertion by advancing the idempotency-bucket clock.
      travel_to(2.minutes.from_now) do
        result = described_class.with(record: pm).deliver(user)
        expect(result).to eq :delivered
      end
      # The after_create_commit on PM also fires the notifier once, so the user
      # has exactly 2 notifications (one auto, one explicit).
      expect(user.notifications.count).to eq 2
    end

    it "auto-populates idempotency_key on the event column" do
      described_class.with(record: project_membership).deliver(user)
      event = Noticed::Event.last
      expect(event.idempotency_key).to be_present
      expect(event.params["idempotency_key"]).to be_nil
    end

    it "deduplicates concurrent dispatches within the same minute" do
      freeze_time do
        described_class.with(record: project_membership).deliver(user)
        result = described_class.with(record: project_membership).deliver(user)
        expect(result).to eq :deduplicated
      end
    end

    it "does not enqueue any NotificationMailer email job (in-app + digest only)" do
      expect {
        described_class.with(record: project_membership).deliver(user)
        perform_enqueued_jobs(only: Noticed::EventJob)
      }.not_to have_enqueued_mail
    end
  end

  describe "preferences gating" do
    let!(:prefs) { create(:user_preferences, user: user) }

    it "respects DND (quiet hours active) for project_activity (does NOT bypass)" do
      # v2: DND is now time-windowed via quiet_hours. Set an always-active
      # window (00:00..23:59) to model the v1 "DND on" semantic.
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge(
          "quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }
        ))
      described_class.with(record: project_membership).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_pref(:in_app)).to be false
      expect(notification.recipient_pref(:email)).to be false
    end

    it "permits in-app + email (instant) under default preferences (project_activity)" do
      # v2: defaults have email.frequency = "instant", so emails fire
      # immediately rather than queuing for digest.
      described_class.with(record: project_membership).deliver(user)
      notification = user.notifications.last
      expect(notification.recipient_pref(:in_app)).to be true
      expect(notification.recipient_pref(:email)).to be true
    end
  end

  describe "#message" do
    it "renders the localized project membership changed message" do
      described_class.with(record: project_membership).deliver(user)
      notification = user.notifications.last
      expect(notification.message).to eq(
        I18n.t("notifications.project_membership_changed.message",
               project: project.name,
               new_role: "Editor")
      )
    end

    it "passes recipient_locale to I18n.t (matches the convention used by sibling notifiers)" do
      # Mirror the locale-fallback pattern from application_notifier_spec.rb:
      # the message must pass `locale: recipient_locale` into I18n.t so the
      # rendered string respects the recipient's prefs.locale rather than the
      # ambient I18n.locale at dispatch time. Verified by intercepting the
      # I18n.t call to assert the keyword is forwarded.
      prefs = create(:user_preferences, user: user)
      prefs.update!(locale: "fr")
      described_class.with(record: project_membership).deliver(user)
      notification = user.notifications.last
      expect(I18n).to receive(:t).with(
        "notifications.project_membership_changed.message",
        hash_including(locale: :fr)
      ).and_call_original
      notification.message
    end
  end

  describe "ProjectMembership callback triggers" do
    it "fires on after_create_commit when a user is added to a project" do
      another_user = create(:user)
      create(:membership, user: another_user, workspace: workspace)
      expect {
        ProjectMembership.create!(project: project, user: another_user, role: "viewer")
      }.to change { Noticed::Event.where(type: described_class.name).count }.by(1)
      expect(another_user.notifications.count).to eq 1
    end

    it "fires on after_update_commit when role changes on a project membership" do
      # Create the PM in one minute bucket, then update in the next so the
      # idempotency_key differs and the second dispatch isn't deduplicated.
      pm = nil
      travel_to(2.minutes.ago) { pm = project_membership }
      expect {
        pm.update!(role: "viewer")
      }.to change { Noticed::Event.where(type: described_class.name).count }.by(1)
    end

    it "does not fire on unrelated updates" do
      project_membership # ensure created (one create-side notification)
      expect {
        project_membership.update!(pinned: true)
      }.not_to change { Noticed::Event.where(type: described_class.name).count }
    end
  end
end

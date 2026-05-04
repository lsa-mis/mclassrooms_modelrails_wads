# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkspaceRoleChangedNotifier, type: :notifier do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  let(:workspace) { create(:workspace) }
  let(:user) { create(:user) }
  let(:initial_role) { Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" } }
  let(:new_role) { Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" } }
  let(:membership) { create(:membership, user: user, workspace: workspace, role: initial_role) }

  # Noticed dispatches an EventJob, which then enqueues a per-channel
  # delivery-method job (Noticed::DeliveryMethods::Email), which finally calls
  # `mail.deliver_later` and enqueues an ActionMailer::MailDeliveryJob. The
  # `have_enqueued_mail` matcher only sees the final MailDeliveryJob, so we
  # must drain BOTH intermediate Noticed jobs in sequence — `perform_enqueued_jobs`
  # only performs jobs already enqueued at call time, not jobs added during the run.
  def drain_noticed_jobs
    perform_enqueued_jobs(only: Noticed::EventJob)
    perform_enqueued_jobs(only: Noticed::DeliveryMethods::Email)
  end

  describe ".category" do
    it "is :account_access" do
      expect(described_class.category_name).to eq "account_access"
    end
  end

  describe "dispatching" do
    it "delivers to the membership's user and creates a Noticed::Notification row" do
      result = described_class.with(record: membership).deliver(user)
      expect(result).to eq :delivered
      expect(user.notifications.count).to eq 1
    end

    it "auto-populates idempotency_key on the event column" do
      described_class.with(record: membership).deliver(user)
      event = Noticed::Event.last
      expect(event.idempotency_key).to be_present
      expect(event.params["idempotency_key"]).to be_nil
    end

    it "deduplicates concurrent dispatches within the same minute" do
      freeze_time do
        described_class.with(record: membership).deliver(user)
        result = described_class.with(record: membership).deliver(user)
        expect(result).to eq :deduplicated
      end
    end

    it "enqueues a NotificationMailer.workspace_role_changed email under default preferences" do
      create(:user_preferences, user: user)
      expect {
        described_class.with(record: membership).deliver(user)
        drain_noticed_jobs
      }.to have_enqueued_mail(NotificationMailer, :workspace_role_changed)
    end
  end

  describe "preferences gating" do
    let!(:prefs) { create(:user_preferences, user: user) }

    it "suppresses both in-app and email under DND (account_access does NOT bypass)" do
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("do_not_disturb" => true))

      expect {
        described_class.with(record: membership).deliver(user)
        drain_noticed_jobs
      }.not_to have_enqueued_mail(NotificationMailer, :workspace_role_changed)

      notification = user.notifications.last
      expect(notification.recipient_pref(:in_app)).to be false
      expect(notification.recipient_pref(:email)).to be false
    end

    it "fires in-app but skips email when account_access.email is false" do
      categories = prefs.notification_preferences["categories"].deep_dup
      categories["account_access"]["email"] = false
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("categories" => categories))

      expect {
        described_class.with(record: membership).deliver(user)
        drain_noticed_jobs
      }.not_to have_enqueued_mail(NotificationMailer, :workspace_role_changed)

      notification = user.notifications.last
      expect(notification.recipient_pref(:in_app)).to be true
      expect(notification.recipient_pref(:email)).to be false
    end
  end

  describe "#message" do
    it "renders the localized role-changed message" do
      membership.update!(role: new_role)
      described_class.with(record: membership).deliver(user)
      notification = user.notifications.last
      expect(notification.message).to eq(
        I18n.t("notifications.workspace_role_changed.message",
               workspace: workspace.name,
               new_role: new_role.name)
      )
    end
  end

  describe "Membership#after_update_commit trigger" do
    it "fires the notifier when role_id changes on a membership" do
      expect {
        membership.update!(role: new_role)
      }.to change { Noticed::Event.where(type: described_class.name).count }.by(1)
      expect(user.notifications.count).to eq 1
    end

    it "does not fire on unrelated updates" do
      membership # ensure created
      expect {
        membership.touch
      }.not_to change { Noticed::Event.where(type: described_class.name).count }
    end
  end
end

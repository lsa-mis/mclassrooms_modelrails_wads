# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkspaceInvitationExpiringSoonNotifier, type: :notifier do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:workspace) { create(:workspace) }
  let(:inviter) { create(:user) }
  # The invitee is resolved by the scheduled sweep job (Task 9, future PR) via
  # User.find_by(email_address: invitation.email). Construct that linkage by
  # hand here so this spec exercises only the dispatch contract.
  let(:invitee) { create(:user) }
  let(:invitation) do
    create(:invitation,
           invitable: workspace,
           email: invitee.email_address,
           invited_by: inviter,
           expires_at: 48.hours.from_now)
  end

  # Drain the EventJob -> per-channel delivery method -> ActionMailer chain
  # in two passes; perform_enqueued_jobs only performs jobs already enqueued
  # at call time, not jobs added during the run.
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
    it "delivers to the invitee and creates a Noticed::Notification row" do
      result = described_class.with(record: invitation).deliver(invitee)
      expect(result).to eq :delivered
      expect(invitee.notifications.count).to eq 1
    end

    it "auto-populates idempotency_key on the event column" do
      described_class.with(record: invitation).deliver(invitee)
      event = Noticed::Event.last
      expect(event.idempotency_key).to be_present
      expect(event.params["idempotency_key"]).to be_nil
    end

    # Day-bucket idempotency: the sweep job (`WorkspaceInvitationExpiringSweepJob`)
    # runs every 6 hours and re-finds every invitation in the 24-hour expiring
    # window on each tick. With the base ApplicationNotifier minute-bucket key
    # this would dispatch ~4 notifications per invitation per day. The override
    # collapses repeat dispatches to one per (invitation, day).
    it "deduplicates two consecutive dispatches hours apart on the same day" do
      midday = Time.current.beginning_of_day + 6.hours
      first = nil
      second = nil
      travel_to(midday) do
        first = described_class.with(record: invitation).deliver(invitee)
      end
      travel_to(midday + 6.hours) do
        second = described_class.with(record: invitation).deliver(invitee)
      end
      expect(first).to eq :delivered
      expect(second).to eq :deduplicated
    end

    it "delivers a fresh dispatch the next day for the same invitation" do
      now = Time.current
      travel_to(now) do
        described_class.with(record: invitation).deliver(invitee)
      end

      travel_to(now + 1.day) do
        result = described_class.with(record: invitation).deliver(invitee)
        expect(result).to eq :delivered
      end
    end

    it "enqueues a NotificationMailer.workspace_invitation_expiring_soon email under default preferences" do
      create(:user_preferences, user: invitee)
      expect {
        described_class.with(record: invitation).deliver(invitee)
        drain_noticed_jobs
      }.to have_enqueued_mail(NotificationMailer, :workspace_invitation_expiring_soon)
    end
  end

  describe "preferences gating" do
    let!(:prefs) { create(:user_preferences, user: invitee) }

    it "suppresses both in-app and email under DND (account_access does NOT bypass)" do
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))

      expect {
        described_class.with(record: invitation).deliver(invitee)
        drain_noticed_jobs
      }.not_to have_enqueued_mail(NotificationMailer, :workspace_invitation_expiring_soon)

      notification = invitee.notifications.last
      expect(notification.recipient_pref(:in_app)).to be false
      expect(notification.recipient_pref(:email)).to be false
    end

    it "fires in-app but skips email when the email channel is disabled" do
      delivery_methods = prefs.notification_preferences["delivery_methods"].deep_dup
      delivery_methods["email"]["enabled"] = false
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("delivery_methods" => delivery_methods))

      expect {
        described_class.with(record: invitation).deliver(invitee)
        drain_noticed_jobs
      }.not_to have_enqueued_mail(NotificationMailer, :workspace_invitation_expiring_soon)

      notification = invitee.notifications.last
      expect(notification.recipient_pref(:in_app)).to be true
      expect(notification.recipient_pref(:email)).to be false
    end
  end

  describe "#message" do
    it "renders the localized expiring-soon message with workspace and hours_remaining" do
      freeze_time do
        invitation_in_window = create(:invitation,
                                      invitable: workspace,
                                      email: invitee.email_address,
                                      invited_by: inviter,
                                      expires_at: 24.hours.from_now)
        described_class.with(record: invitation_in_window).deliver(invitee)
        notification = invitee.notifications.last
        expect(notification.message).to eq(
          I18n.t("notifications.workspace_invitation_expiring_soon.message",
                 workspace: workspace.name,
                 hours_remaining: 24)
        )
      end
    end
  end
end

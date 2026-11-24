# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkspaceInvitationExpiringSoonNotifier, type: :notifier do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  def expiring_invitation(invitee, inviter: create(:user), invitable: create(:workspace), **attrs)
    create(:invitation,
           **{ invitable: invitable,
               email: invitee.email_address,
               invited_by: inviter,
               expires_at: 48.hours.from_now }.merge(attrs))
  end

  describe ".category" do
    it "is :account_access" do
      expect(described_class.category_name).to eq "account_access"
    end
  end

  describe "dispatching" do
    it "delivers to the invitee and creates a Noticed::Notification row" do
      invitee = create(:user)
      invitation = expiring_invitation(invitee)
      result = described_class.with(record: invitation).deliver(invitee)
      expect(result).to eq :delivered
      expect(invitee.notifications.count).to eq 1
    end

    it "auto-populates idempotency_key on the event column" do
      invitee = create(:user)
      invitation = expiring_invitation(invitee)
      described_class.with(record: invitation).deliver(invitee)
      event = Noticed::Event.last
      expect(event.idempotency_key).to be_present
      expect(event.params["idempotency_key"]).to be_nil
    end

    # Day-bucket idempotency: the 6-hourly sweep job re-finds each expiring
    # invitation, so repeat dispatches collapse to one per (invitation, day).
    it "deduplicates two consecutive dispatches hours apart on the same day" do
      invitee = create(:user)
      midday = Time.current.beginning_of_day + 6.hours
      invitation = first = second = nil
      travel_to(midday) do
        invitation = expiring_invitation(invitee)
        first = described_class.with(record: invitation).deliver(invitee)
      end
      travel_to(midday + 6.hours) do
        second = described_class.with(record: invitation).deliver(invitee)
      end
      expect(first).to eq :delivered
      expect(second).to eq :deduplicated
    end

    it "delivers a fresh dispatch the next day for the same invitation" do
      invitee = create(:user)
      now = Time.current
      invitation = nil
      travel_to(now) do
        invitation = expiring_invitation(invitee)
        described_class.with(record: invitation).deliver(invitee)
      end

      travel_to(now + 1.day) do
        result = described_class.with(record: invitation).deliver(invitee)
        expect(result).to eq :delivered
      end
    end

    it "enqueues a NotificationMailer.workspace_invitation_expiring_soon email under default preferences" do
      invitee = create(:user)
      create(:user_preferences, user: invitee)
      invitation = expiring_invitation(invitee)
      expect {
        described_class.with(record: invitation).deliver(invitee)
        drain_noticed_jobs
      }.to have_enqueued_mail(NotificationMailer, :workspace_invitation_expiring_soon)
    end

    # Scoped to MailDeliveryJob: a bare perform_enqueued_jobs also runs
    # CheckGravatarJob (network IO) from the user factories.
    it "does not email when the block lands after dispatch (T14, final-hop gate)" do
      invitee = create(:user)
      invitation = expiring_invitation(invitee)
      inviter = invitation.invited_by
      described_class.with(record: invitation).deliver(invitee)
      create(:invitation_block, inviter: inviter, email: invitation.email)

      expect {
        drain_noticed_jobs                                             # EventJob → Email method
        perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob)      # → ActionMailer job
      }.not_to change { ActionMailer::Base.deliveries.count }
    end
  end

  describe "preferences gating" do
    it "suppresses both in-app and email under DND (account_access does NOT bypass)" do
      invitee = create(:user)
      prefs = create(:user_preferences, user: invitee)
      invitation = expiring_invitation(invitee)
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
      invitee = create(:user)
      prefs = create(:user_preferences, user: invitee)
      invitation = expiring_invitation(invitee)
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
      workspace = create(:workspace)
      invitee = create(:user)
      freeze_time do
        invitation_in_window = expiring_invitation(invitee, invitable: workspace, expires_at: 24.hours.from_now)
        described_class.with(record: invitation_in_window).deliver(invitee)
        notification = invitee.notifications.last
        expect(notification.message).to eq(
          I18n.t("notifications.workspace_invitation_expiring_soon.message",
                 workspace_name: workspace.name,
                 hours_remaining: 24)
        )
      end
    end
  end

  describe "#url" do
    it "links to the accept-invitation path with the invitation token" do
      invitee = create(:user)
      invitation = expiring_invitation(invitee)
      described_class.with(record: invitation).deliver(invitee)
      notification = invitee.notifications.last
      expect(notification.url).to eq(
        Rails.application.routes.url_helpers.accept_invitation_path(token: invitation.token)
      )
    end

    it "returns the placeholder copy when the invitation has been deleted" do
      invitee = create(:user)
      invitation = expiring_invitation(invitee)
      described_class.with(record: invitation).deliver(invitee)
      invitation.destroy
      notification = invitee.notifications.last
      expect(notification.url).to eq(I18n.t("notifications.placeholder"))
    end
  end
end

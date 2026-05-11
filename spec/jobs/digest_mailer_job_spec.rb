# frozen_string_literal: true

require "rails_helper"

RSpec.describe DigestMailerJob, type: :job do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  let(:user) { create(:user) }
  let(:eligible_workspace) { create(:workspace) }
  let(:invitation) {
    create(:invitation, invitable: eligible_workspace, email: user.email_address, invited_by: create(:user))
  }

  before do
    Noticed::Notification.delete_all
    Noticed::Event.delete_all
    clear_enqueued_jobs
    user.create_preferences!(timezone: "UTC")
  end

  describe "#perform" do
    context "user is due for digest" do
      before do
        # v2 default frequency is "instant" — digest_enabled? would return
        # false and the job would short-circuit. Bump the user into "daily"
        # to exercise the digest delivery path.
        np = user.preferences.notification_preferences.deep_dup
        np["delivery_methods"]["email"]["frequency"] = "daily"
        user.preferences.update!(notification_preferences: np, digest_next_due_at: 1.minute.ago)
      end

      it "enqueues the digest mailer when there are unseen eligible notifications" do
        WorkspaceInvitationAcceptedNotifier
          .with(record: invitation)
          .deliver(user)

        expect {
          described_class.perform_now
        }.to have_enqueued_mail(NotificationMailer, :digest)
      end

      it "marks included notifications seen after successful enqueue" do
        WorkspaceInvitationAcceptedNotifier
          .with(record: invitation)
          .deliver(user)
        notification = user.notifications.first
        expect(notification.seen_at).to be_nil

        described_class.perform_now

        expect(notification.reload.seen_at).to be_present
      end

      it "skips the user entirely when DND is on (no mail, no seen, but bumps next_due)" do
        WorkspaceInvitationAcceptedNotifier
          .with(record: invitation)
          .deliver(user)
        prefs = user.preferences.notification_preferences
        user.preferences.update!(notification_preferences: prefs.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))
        previous_due = user.preferences.digest_next_due_at

        expect {
          described_class.perform_now
        }.not_to have_enqueued_mail(NotificationMailer, :digest)

        expect(user.notifications.first.reload.seen_at).to be_nil
        expect(user.preferences.reload.digest_next_due_at).to be > previous_due
      end

      it "skips when digest is disabled in preferences (frequency back to instant)" do
        WorkspaceInvitationAcceptedNotifier
          .with(record: invitation)
          .deliver(user)
        # The before block sets frequency = "daily"; flip it back to "instant"
        # to disable digest for this user. digest_enabled? is now false.
        np = user.preferences.notification_preferences.deep_dup
        np["delivery_methods"]["email"]["frequency"] = "instant"
        user.preferences.update!(notification_preferences: np)

        expect {
          described_class.perform_now
        }.not_to have_enqueued_mail(NotificationMailer, :digest)
      end

      it "skips empty windows but still bumps digest_next_due_at" do
        previous_due = user.preferences.digest_next_due_at
        previous_sent = user.preferences.digest_last_sent_at

        expect {
          described_class.perform_now
        }.not_to have_enqueued_mail(NotificationMailer, :digest)

        user.preferences.reload
        expect(user.preferences.digest_next_due_at).to be > Time.current
        expect(user.preferences.digest_next_due_at).not_to eq(previous_due)
        expect(user.preferences.digest_last_sent_at).to eq(previous_sent)
      end

      it "excludes notifications that already have seen_at set (digest dedupe)" do
        WorkspaceInvitationAcceptedNotifier
          .with(record: invitation)
          .deliver(user)
        user.notifications.update_all(seen_at: 5.minutes.ago)

        expect {
          described_class.perform_now
        }.not_to have_enqueued_mail(NotificationMailer, :digest)
      end

      it "excludes non-digest-eligible categories (security stays out of digest)" do
        # PasswordChangedNotifier is :security category — never digestable.
        PasswordChangedNotifier.with(record: user).deliver(user)

        expect {
          described_class.perform_now
        }.not_to have_enqueued_mail(NotificationMailer, :digest)
      end

      it "bumps digest_last_sent_at when a digest is enqueued" do
        WorkspaceInvitationAcceptedNotifier
          .with(record: invitation)
          .deliver(user)
        previous_sent = user.preferences.digest_last_sent_at

        described_class.perform_now

        expect(user.preferences.reload.digest_last_sent_at).not_to eq(previous_sent)
        expect(user.preferences.digest_last_sent_at).to be_within(5.seconds).of(Time.current)
      end
    end

    context "user is NOT due for digest" do
      it "skips the user entirely (no mail, timestamps unchanged)" do
        user.preferences.update!(digest_next_due_at: 1.day.from_now)
        previous_due = user.preferences.digest_next_due_at

        expect {
          described_class.perform_now
        }.not_to have_enqueued_mail(NotificationMailer, :digest)

        expect(user.preferences.reload.digest_next_due_at).to eq(previous_due)
      end
    end

    context "uses a single indexed range scan, not per-user polling" do
      it "issues exactly one users.joins(:user_preferences) call" do
        # Two due users + one not-due user; verify the join-scan is the only
        # query pattern used to find candidates.
        user.preferences.update!(digest_next_due_at: 1.minute.ago)
        other = create(:user)
        other.create_preferences!(timezone: "UTC", digest_next_due_at: 1.minute.ago)
        not_due = create(:user)
        not_due.create_preferences!(timezone: "UTC", digest_next_due_at: 1.day.from_now)

        expect(User).to receive(:joins).with(:preferences).and_call_original

        described_class.perform_now
      end
    end
  end
end

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

      # The job no longer marks anything on the notification itself (D10) — the
      # dedupe between cycles is the watermark on the user's preferences, and
      # what suppresses an item is the recipient reading it.
      it "advances the cycle watermark after a successful enqueue" do
        WorkspaceInvitationAcceptedNotifier
          .with(record: invitation)
          .deliver(user)
        expect(user.preferences.digest_last_sent_at).to be_nil

        # travel, not freeze_time: the window is half-open, so a row created in
        # the same second as the cycle start is deferred to the next cycle by
        # design. Second-granularity timestamps make that a coin flip unless
        # the two are deliberately separated.
        travel 1.minute do
          described_class.perform_now
          expect(user.preferences.reload.digest_last_sent_at)
            .to be_within(1.second).of(Time.current)
        end
      end

      it "skips the user entirely when DND is on (no mail, watermark untouched, but bumps next_due)" do
        WorkspaceInvitationAcceptedNotifier
          .with(record: invitation)
          .deliver(user)
        prefs = user.preferences.notification_preferences
        user.preferences.update!(notification_preferences: prefs.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))
        previous_due = user.preferences.digest_next_due_at

        expect {
          described_class.perform_now
        }.not_to have_enqueued_mail(NotificationMailer, :digest)

        expect(user.preferences.reload.digest_last_sent_at).to be_nil
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

      # Cycle dedupe is the watermark: anything created at or before the last
      # cycle's start has already had its chance to be digested.
      it "excludes notifications older than the cycle watermark" do
        WorkspaceInvitationAcceptedNotifier
          .with(record: invitation)
          .deliver(user)
        user.preferences.update!(digest_last_sent_at: 1.minute.from_now)

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

  # D10: the digest keys off READ state, not a "seen" stamp the job wrote to
  # itself, and its cycle watermark is half-open so nothing falls in the gap.
  describe "digest correctness (D10)" do
    before do
      np = user.preferences.notification_preferences.deep_dup
      np["delivery_methods"]["email"]["frequency"] = "daily"
      user.preferences.update!(notification_preferences: np, digest_next_due_at: 1.minute.ago)
    end

    # A distinct notification per call. ApplicationNotifier dedupes on
    # (class, record, minute bucket), so delivering the same invitation twice
    # in one example collapses into a single row — which silently turns a
    # two-item assertion into a one-item one.
    def deliver_one
      before = user.notifications.pluck(:id)
      WorkspaceInvitationAcceptedNotifier
        .with(record: create(:invitation, invitable: create(:workspace),
                             email: user.email_address, invited_by: create(:user)))
        .deliver(user)
      user.notifications.where.not(id: before).sole
    end

    it "excludes notifications the recipient has already read" do
      deliver_one.update!(read_at: Time.current)

      expect { described_class.perform_now }
        .not_to have_enqueued_mail(NotificationMailer, :digest)
    end

    # The watermark is captured BEFORE the select and stamped after, so the
    # window is [floor, cycle_started_at). Stamping Time.current after delivery
    # instead would swallow anything that arrived while the mail was being
    # built — it would sit below the new watermark having never been selected.
    it "carries a row that arrives mid-cycle into the next digest instead of dropping it" do
      deliver_one

      allow(NotificationMailer).to receive(:digest).and_wrap_original do |orig, *args|
        travel 1.minute
        deliver_one
        orig.call(*args)
      end

      described_class.perform_now
      clear_enqueued_jobs
      allow(NotificationMailer).to receive(:digest).and_call_original

      user.preferences.update!(digest_next_due_at: 1.minute.ago)

      expect { described_class.perform_now }
        .to have_enqueued_mail(NotificationMailer, :digest)
    end

    # The whole point of passing ids: an AR object serialises as a GlobalID,
    # and retention deleting the row between enqueue and render raises
    # DeserializationError, which dead-letters the ENTIRE digest — the other
    # notifications in it are never delivered.
    it "still delivers when a selected row is deleted before the mail renders" do
      kept = deliver_one
      doomed = deliver_one

      described_class.perform_now
      doomed.destroy!

      expect { perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) }.not_to raise_error
      expect(ActionMailer::Base.deliveries.last.to).to eq([ user.email_address ])
      expect(user.notifications.where(id: kept.id)).to exist
    end
  end

  # D10: the mailer is the last gate — it re-queries at render time, because a
  # user can read an item between the job selecting it and the mail going out.
  describe "delivery-time re-check" do
    # A distinct notification per call. ApplicationNotifier dedupes on
    # (class, record, minute bucket), so delivering the same invitation twice
    # in one example collapses into a single row — which silently turns a
    # two-item assertion into a one-item one.
    def deliver_one
      before = user.notifications.pluck(:id)
      WorkspaceInvitationAcceptedNotifier
        .with(record: create(:invitation, invitable: create(:workspace),
                             email: user.email_address, invited_by: create(:user)))
        .deliver(user)
      user.notifications.where.not(id: before).sole
    end

    it "renders only the ids still unread at delivery" do
      unread = deliver_one
      read_since = deliver_one
      read_since.update!(read_at: Time.current)

      mail = NotificationMailer.digest(user, [ unread.id, read_since.id ])

      # Both ids were selected; only the still-unread one survives the
      # delivery-time re-query, so the digest describes one item, not two.
      expect(mail.to).to eq([ user.email_address ])
      expect(mail.body.encoded)
        .to include(I18n.t("notification_mailer.digest.preheader", count: 1))
    end

    it "sends nothing when every selected id has been read since" do
      read_since = deliver_one
      read_since.update!(read_at: Time.current)

      mail = NotificationMailer.digest(user, [ read_since.id ])

      expect(mail.message).to be_a(ActionMailer::Base::NullMail)
    end
  end
end

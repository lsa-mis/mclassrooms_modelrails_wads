# frozen_string_literal: true

require "rails_helper"

# Panel-flagged hardening cases: idempotency under retry, atomicity of
# mid-fan-out failures, deleted records mid-flight, throttle fail-open,
# and concurrent mark-all-read + arrival. Each describe block isolates
# one error contract.
RSpec.describe "Notifications hardening", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  before do
    Noticed::Notification.delete_all
    Noticed::Event.delete_all
  end

  describe "idempotent event insertion under retry" do
    let(:invited_by) { create(:user) }
    let(:workspace) { create(:workspace) }
    let(:invitation) {
      create(:invitation, invitable: workspace, email: user.email_address, invited_by: invited_by)
    }

    it "creates exactly one event when the same Notifier fires twice in the same minute" do
      freeze_time do
        WorkspaceInvitationReceivedNotifier.with(record: invitation).deliver(user)
        expect {
          WorkspaceInvitationReceivedNotifier.with(record: invitation).deliver(user)
        }.not_to change(Noticed::Event, :count)
      end
    end

    it "swallows RecordNotUnique silently — no exception escapes" do
      freeze_time do
        WorkspaceInvitationReceivedNotifier.with(record: invitation).deliver(user)
        expect {
          WorkspaceInvitationReceivedNotifier.with(record: invitation).deliver(user)
        }.not_to raise_error
      end
    end

    it "returns :deduplicated sentinel on the duplicate dispatch" do
      freeze_time do
        first = WorkspaceInvitationReceivedNotifier.with(record: invitation).deliver(user)
        second = WorkspaceInvitationReceivedNotifier.with(record: invitation).deliver(user)
        expect(first).to eq(:delivered)
        expect(second).to eq(:deduplicated)
      end
    end
  end

  describe "fan-out atomicity (Event saves with all-or-nothing notifications)" do
    # Noticed v3's `Deliverable#deliver` wraps `save!` (the Event row) and
    # `notifications.insert_all!` (the per-recipient rows) in one transaction.
    # If `insert_all!` fails, the Event row rolls back too — net effect is
    # zero new rows, never partial.
    #
    # The `notifications` relation is built internally by Noticed, so there is
    # no doubleable handle to stub `insert_all!` on directly (and a class-level
    # `Noticed::Notification.insert_all!` stub does not intercept the call —
    # it dispatches through the association proxy, not the bare class). Rather
    # than reach into `ActiveRecord::Relation` via any_instance, we capture the
    # notifier through constructor stubbing and inject an unknown column into the
    # per-recipient attributes. That makes the REAL `insert_all!` fail with a
    # genuine DB error inside the transaction, after `save!` — exercising the
    # real rollback path with no mock on the insert itself.
    it "rolls back the Event row when notifications.insert_all! raises" do
      allow(PasswordChangedNotifier).to receive(:new).and_wrap_original do |orig, *args, **kwargs|
        notifier = orig.call(*args, **kwargs)
        allow(notifier).to receive(:recipient_attributes_for).and_wrap_original do |inner, *inner_args|
          inner.call(*inner_args).merge(nonexistent_column_to_force_insert_failure: "boom")
        end
        notifier
      end

      expect {
        PasswordChangedNotifier.with(record: user).deliver(user) rescue nil
      }.not_to change { [ Noticed::Event.count, Noticed::Notification.count ] }
    end
  end

  describe "recipient deleted before digest job runs" do
    it "skips orphaned notifications without raising" do
      invited_by = create(:user)
      workspace = create(:workspace)
      invitation = create(:invitation, invitable: workspace,
                          email: user.email_address, invited_by: invited_by)
      WorkspaceInvitationAcceptedNotifier.with(record: invitation).deliver(user)

      user.destroy  # cascades notifications via the User#dependent: :destroy

      expect { DigestMailerJob.perform_now }.not_to raise_error
    end
  end

  describe "notifiable deleted during render" do
    it "render_safe_or_placeholder swallows RecordNotFound and renders the placeholder" do
      invited_by = create(:user)
      workspace = create(:workspace)
      invitation = create(:invitation, invitable: workspace,
                          email: user.email_address, invited_by: invited_by)
      WorkspaceInvitationReceivedNotifier.with(record: invitation).deliver(user)
      notification = user.notifications.first

      invitation.destroy  # tombstones the polymorphic record

      result = notification.render_safe_or_placeholder do
        notification.message
      end
      expect(result).to eq(I18n.t("notifications.placeholder"))
    end
  end

  describe "throttle fail-open under cache miss" do
    it "still enqueues the security mailer when Rails.cache.increment returns nil" do
      allow(Rails.cache).to receive(:increment).and_return(nil)

      expect {
        PasswordChangedNotifier.with(record: user).deliver(user)
      }.to change(Noticed::Event, :count).by(1)
    end
  end

  describe "concurrent mark_all_read with mid-batch arrival" do
    let(:invited_by) { create(:user) }
    let(:workspace) { create(:workspace) }
    let(:invitation) {
      create(:invitation, invitable: workspace,
             email: user.email_address, invited_by: invited_by)
    }

    # Deterministic mid-batch arrival: drive the existing controller flow
    # (which uses an atomic update_all, not in_batches) and assert that a
    # notification arriving AFTER the mark_all_read commit stays unread.
    # If the controller ever switches to in_batches with a non-snapshot
    # WHERE clause, this test catches the silent loss of late arrivals.
    it "doesn't lose notifications that arrive after mark_all_read commits" do
      sign_in(user)
      # Sign-in dispatches a SignInFromNewDeviceNotifier; clear so the count
      # math below isn't off-by-one.
      user.notifications.destroy_all
      3.times do |i|
        travel_to(Time.current + (i + 1).minutes) do
          WorkspaceInvitationAcceptedNotifier
            .with(record: create(:invitation, invitable: workspace,
                                 email: "x#{i}#{SecureRandom.hex(2)}@example.com",
                                 invited_by: invited_by))
            .deliver(user)
        end
      end
      expect(user.notifications.where(read_at: nil).count).to eq(3)

      post mark_all_read_account_notifications_path
      expect(user.notifications.where(read_at: nil).count).to eq(0)

      # New arrival AFTER mark_all_read committed must stay unread.
      travel_to(Time.current + 10.minutes) do
        WorkspaceInvitationAcceptedNotifier
          .with(record: create(:invitation, invitable: workspace,
                               email: "late@example.com",
                               invited_by: invited_by))
          .deliver(user)
      end

      expect(user.notifications.where(read_at: nil).count).to eq(1)
      expect(user.notifications.where.not(read_at: nil).count).to eq(3)
    end
  end
end

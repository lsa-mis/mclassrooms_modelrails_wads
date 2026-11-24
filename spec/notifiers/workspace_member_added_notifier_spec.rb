# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkspaceMemberAddedNotifier, type: :notifier do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  def member_added_cast
    owner_user_a = create(:user)
    owner_user_b = create(:user)
    added_user = create(:user)
    workspace = create(:workspace)
    owner_a_membership = create(:membership, :owner, user: owner_user_a, workspace: workspace)
    owner_b_membership = create(:membership, :owner, user: owner_user_b, workspace: workspace)
    Noticed::Notification.delete_all
    Noticed::Event.delete_all
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs
    { workspace: workspace, owner_user_a: owner_user_a, owner_user_b: owner_user_b, added_user: added_user,
      owner_a_membership: owner_a_membership, owner_b_membership: owner_b_membership }
  end

  # Triggers WorkspaceMemberAddedNotifier via after_create_commit.
  def add_member!(workspace, user)
    create(:membership, user: user, workspace: workspace)
  end

  def admit_as_member(workspace, user, **options)
    workspace.admit(user, role: build(:membership).role, **options)
  end

  describe ".category" do
    it "is :workspace_activity" do
      expect(described_class.category_name).to eq "workspace_activity"
    end
  end

  # Spec case 1: Recipient resolution returns added_user + owners-excluding-added-user, deduped.
  # The added-user + owners fan-out is asserted through the real dispatch —
  # "creates exactly one Noticed::Notification row for the added user" and
  # "…for each owner" below — so only the dedup edge case lives here.
  describe "recipient resolution" do
    it "deduplicates when the added user is themselves an owner of the workspace" do
      owner_user_a, owner_user_b, owner_a_membership = member_added_cast.values_at(:owner_user_a, :owner_user_b, :owner_a_membership)
      # Edge case: simulate "added user is already an owner" by passing an
      # existing owner's membership through the resolver. The candidate list
      # would be [owner_user_a, owner_user_a, owner_user_b] without dedup.
      # evaluate_recipients is public API on Noticed::Deliverable — no `send`
      # needed. Kept as the subject (rather than counting delivered rows)
      # because `.uniq` in the recipients block is what this pins, and
      # noticed_notifications has no unique index on (event_id, recipient).
      event = described_class.with(record: owner_a_membership)
      recipients = event.evaluate_recipients
      expect(recipients.count(owner_user_a)).to eq 1
      expect(recipients).to match_array([ owner_user_a, owner_user_b ])
    end
  end

  # 37signals rule (Fizzy/Campfire): you are never notified about your own
  # action. The actor rides as an event PARAM, not off `record.granted_by` —
  # that attr_accessor is non-persisted, so an exclusion keyed on it would
  # silently exclude nobody the moment recipient resolution moved off the
  # in-memory record.
  describe "actor exclusion" do
    it "drops the owner who performed the add, keeping the added user and the other owners" do
      workspace, owner_user_a, owner_user_b, added_user = member_added_cast.values_at(:workspace, :owner_user_a, :owner_user_b, :added_user)
      admit_as_member(workspace, added_user, granted_by: owner_user_a)

      recipients = Noticed::Notification
        .where(type: "#{described_class.name}::Notification")
        .includes(:recipient).map(&:recipient)
      expect(recipients).to contain_exactly(added_user, owner_user_b)
    end

    it "persists the actor on the event so resolution never depends on a transient attribute" do
      workspace, owner_user_a, added_user = member_added_cast.values_at(:workspace, :owner_user_a, :added_user)
      admit_as_member(workspace, added_user, granted_by: owner_user_a)

      event = Noticed::Event.where(type: described_class.name).last
      expect(event.reload.params[:actor]).to eq(owner_user_a)
    end

    it "notifies everyone when there is no actor (system-seeded grant)" do
      workspace, owner_user_a, owner_user_b, added_user = member_added_cast.values_at(:workspace, :owner_user_a, :owner_user_b, :added_user)
      admit_as_member(workspace, added_user)

      recipients = Noticed::Notification
        .where(type: "#{described_class.name}::Notification")
        .includes(:recipient).map(&:recipient)
      expect(recipients).to contain_exactly(added_user, owner_user_a, owner_user_b)
    end

    it "drops the actor even when they are the only owner left, leaving just the added user" do
      workspace, owner_user_a, added_user, owner_b_membership = member_added_cast.values_at(:workspace, :owner_user_a, :added_user, :owner_b_membership)
      # Ada (owner_user_a) re-adds herself is impossible; the real shape is a
      # lone-owner workspace where the owner adds the only other person —
      # "the actor is gone from the list even when they are the whole rest of
      # it". The full recipient set is pinned, not just the actor's own count:
      # asserting only `owner_user_a.count == 0` also passed when the fan-out
      # was empty, or when it had reached someone it should not have.
      owner_b_membership.deactivate!
      admit_as_member(workspace, added_user, granted_by: owner_user_a)

      expect(
        Noticed::Notification.where(type: "#{described_class.name}::Notification")
          .includes(:recipient).map(&:recipient)
      ).to eq([ added_user ])
    end
  end

  # Spec case 2: Added user receives one in-app notification.
  describe "added user — in-app" do
    it "creates exactly one Noticed::Notification row for the added user" do
      workspace, added_user = member_added_cast.values_at(:workspace, :added_user)
      add_member!(workspace, added_user)
      expect(
        Noticed::Notification.where(recipient: added_user, type: "#{described_class.name}::Notification").count
      ).to eq 1
    end
  end

  # Spec case 3: Added user receives one email job.
  describe "added user — email" do
    it "enqueues exactly one NotificationMailer.workspace_member_added targeting the added user" do
      workspace, added_user = member_added_cast.values_at(:workspace, :added_user)
      added_user_email = added_user.email_address

      # v2 default prefs have workspace_activity on + email channel on at
      # "instant" frequency, so the happy path needs no explicit setup.
      # The opt-out side of this split is covered in the preference-gating
      # block below.

      expect {
        add_member!(workspace, added_user)
        drain_noticed_jobs
      }.to have_enqueued_mail(NotificationMailer, :workspace_member_added).once

      # Drain the final ActionMailer::MailDeliveryJob so we can inspect the
      # rendered envelope and confirm the recipient address.
      perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob)
      delivered_to = ActionMailer::Base.deliveries.flat_map(&:to)
      expect(delivered_to).to eq([ added_user_email ])
    end
  end

  # Spec case 4: Each owner gets one in-app notification.
  describe "owner — in-app" do
    it "creates exactly one Noticed::Notification row for each owner" do
      workspace, owner_user_a, owner_user_b, added_user = member_added_cast.values_at(:workspace, :owner_user_a, :owner_user_b, :added_user)
      add_member!(workspace, added_user)
      expect(
        Noticed::Notification.where(recipient: owner_user_a, type: "#{described_class.name}::Notification").count
      ).to eq 1
      expect(
        Noticed::Notification.where(recipient: owner_user_b, type: "#{described_class.name}::Notification").count
      ).to eq 1
    end
  end

  # Spec case 5: Owners do NOT receive a workspace_member_added email.
  describe "owner — NO email" do
    it "does not enqueue any NotificationMailer.workspace_member_added job for owner emails" do
      workspace, owner_user_a, owner_user_b, added_user = member_added_cast.values_at(:workspace, :owner_user_a, :owner_user_b, :added_user)
      owner_emails = [ owner_user_a.email_address, owner_user_b.email_address ]
      add_member!(workspace, added_user)
      drain_noticed_jobs
      perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob)

      delivered_to_owners = ActionMailer::Base.deliveries.flat_map(&:to) & owner_emails
      expect(delivered_to_owners).to be_empty
    end
  end

  # Spec case 6: Owner notifications remain unseen post-deliver (digest pipeline eligibility).
  describe "owner — digest eligibility" do
    # Digest eligibility is read state now (D10): seen_at is gone, and an
    # unread notification inside the cycle window is what the digest picks up.
    it "leaves owner notifications unread post-deliver, so the digest can pick them up" do
      workspace, owner_user_a, owner_user_b, added_user = member_added_cast.values_at(:workspace, :owner_user_a, :owner_user_b, :added_user)
      add_member!(workspace, added_user)
      drain_noticed_jobs
      [ owner_user_a, owner_user_b ].each do |o|
        notif = Noticed::Notification.where(recipient: o, type: "#{described_class.name}::Notification").last
        expect(notif).not_to be_nil
        expect(notif.read_at).to be_nil
      end
    end
  end

  # Spec case 7: Email gating — workspace_activity on (default) vs disabled.
  describe "preference gating — added user workspace_activity category" do
    it "enqueues the email under v2 defaults (workspace_activity on, email channel on)" do
      workspace, added_user = member_added_cast.values_at(:workspace, :added_user)
      create(:user_preferences, user: added_user) # v2 default: everything on

      expect {
        add_member!(workspace, added_user)
        drain_noticed_jobs
      }.to have_enqueued_mail(NotificationMailer, :workspace_member_added).once
    end

    it "does not enqueue the email when the added user disables the workspace_activity category" do
      workspace, added_user = member_added_cast.values_at(:workspace, :added_user)
      prefs = create(:user_preferences, user: added_user)
      np = prefs.notification_preferences.deep_dup
      np["notification_types"]["workspace_activity"] = false
      prefs.update!(notification_preferences: np)

      expect {
        add_member!(workspace, added_user)
        drain_noticed_jobs
      }.not_to have_enqueued_mail(NotificationMailer, :workspace_member_added)
    end

    it "defers the email when email frequency is non-instant (DigestMailerJob picks it up)" do
      workspace, added_user = member_added_cast.values_at(:workspace, :added_user)
      # v2 tri-state contract: when allow?(email) returns :digest, the immediate
      # mailer must NOT enqueue — DigestMailerJob's next cycle delivers it. A
      # truthy-check `unless recipient_pref(:email)` would treat :digest as
      # truthy and incorrectly fire the immediate send, breaking the entire
      # frequency feature. Pins the `== true` guard contract.
      prefs = create(:user_preferences, user: added_user)
      np = prefs.notification_preferences.deep_dup
      np["delivery_methods"]["email"]["frequency"] = "daily"
      prefs.update!(notification_preferences: np)

      expect {
        add_member!(workspace, added_user)
        drain_noticed_jobs
      }.not_to have_enqueued_mail(NotificationMailer, :workspace_member_added)
    end
  end

  # Spec case 8: Owner who disables the in_app channel does NOT get an in-app row;
  # other owners + added user are unaffected.
  describe "preference gating — owner in-app channel" do
    it "skips in-app for the disabling owner; other owners + added user still receive theirs" do
      workspace, owner_user_a, owner_user_b, added_user = member_added_cast.values_at(:workspace, :owner_user_a, :owner_user_b, :added_user)
      prefs_a = create(:user_preferences, user: owner_user_a)
      delivery_methods = prefs_a.notification_preferences["delivery_methods"].deep_dup
      delivery_methods["in_app"]["enabled"] = false
      prefs_a.update!(notification_preferences:
        prefs_a.notification_preferences.merge("delivery_methods" => delivery_methods))

      add_member!(workspace, added_user)

      expect(Noticed::Notification.where(recipient: owner_user_a,
                                          type: "#{described_class.name}::Notification").count).to eq 0
      expect(Noticed::Notification.where(recipient: owner_user_b,
                                          type: "#{described_class.name}::Notification").count).to eq 1
      expect(Noticed::Notification.where(recipient: added_user,
                                          type: "#{described_class.name}::Notification").count).to eq 1
    end
  end

  # Spec case 9: DND on for added user — no email AND no in-app.
  describe "DND — added user" do
    it "suppresses both email and in-app for the added user (workspace_activity does NOT bypass DND)" do
      workspace, added_user = member_added_cast.values_at(:workspace, :added_user)
      prefs = create(:user_preferences, user: added_user)
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))

      expect {
        add_member!(workspace, added_user)
        drain_noticed_jobs
      }.not_to have_enqueued_mail(NotificationMailer, :workspace_member_added)

      expect(Noticed::Notification.where(recipient: added_user,
                                          type: "#{described_class.name}::Notification").count).to eq 0
    end
  end

  # Spec case 10: Single noticed_events row per dispatch regardless of recipient count.
  describe "single event row" do
    it "creates exactly one Noticed::Event row per dispatch (even with multiple recipients)" do
      workspace, added_user = member_added_cast.values_at(:workspace, :added_user)
      expect {
        add_member!(workspace, added_user)
      }.to change { Noticed::Event.where(type: described_class.name).count }.by(1)
    end
  end

  describe "Membership#after_create_commit trigger" do
    it "fires the notifier when a new membership is created" do
      workspace, added_user = member_added_cast.values_at(:workspace, :added_user)
      expect {
        add_member!(workspace, added_user)
      }.to change { Noticed::Event.where(type: described_class.name).count }.by(1)
    end

    it "does not fire on subsequent updates to an existing membership" do
      workspace, added_user = member_added_cast.values_at(:workspace, :added_user)
      m = add_member!(workspace, added_user)
      expect {
        m.touch
      }.not_to change { Noticed::Event.where(type: described_class.name).count }
    end
  end
  # #920. The row outlives the workspace it points at, and #url may not raise
  # out of the notifications index or the digest render — the digest wraps
  # RENDERING, not URL generation, so one stale row takes down a whole
  # recipient's digest rather than just its own line.
  describe "#url once the workspace is gone" do
    it "renders the placeholder instead of raising" do
      workspace, added_user = member_added_cast.values_at(:workspace, :added_user)
      add_member!(workspace, added_user)
      notification = Noticed::Event.where(type: described_class.name).last.notifications.first
      workspace.destroy!

      expect(notification.reload.url).to eq(I18n.t("notifications.placeholder"))
    end
  end
end

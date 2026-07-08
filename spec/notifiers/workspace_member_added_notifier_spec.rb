# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkspaceMemberAddedNotifier, type: :notifier do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  # Drain only the Noticed-pipeline jobs that fan out to ActionMailer; we
  # deliberately do NOT call the un-scoped `perform_enqueued_jobs` because that
  # would also run unrelated jobs like CheckGravatarJob (enqueued from the user
  # factory) which does network IO and isn't relevant to this notifier.
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
  let(:member_role) do
    Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
  end

  let(:workspace) { create(:workspace) }

  # All three of these MUST be `let!`. The User factory's `after_create
  # :create_personal_workspace` callback creates a personal Workspace +
  # Membership for every new User, and that Membership creation fires THIS
  # notifier. If `added_user` were lazy, its first reference inside the
  # `it` block would create a personal-workspace membership *during* the
  # action under test, polluting the event count for that example.
  let!(:owner_user_a) { create(:user) }
  let!(:owner_user_b) { create(:user) }
  let!(:added_user) { create(:user) }
  let!(:owner_a_membership) { create(:membership, user: owner_user_a, workspace: workspace, role: owner_role) }
  let!(:owner_b_membership) { create(:membership, user: owner_user_b, workspace: workspace, role: owner_role) }

  # Reset notification state created by the user/owner setup. Each User factory
  # call triggers a personal-workspace Membership creation which dispatches this
  # notifier (4 events from the 5 setup memberships, in fact). We need a clean
  # slate before each example to assert on its own dispatch.
  before do
    Noticed::Notification.delete_all
    Noticed::Event.delete_all
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs
  end

  # Triggers WorkspaceMemberAddedNotifier via after_create_commit.
  def add_member!(user: added_user, role: member_role)
    create(:membership, user: user, workspace: workspace, role: role)
  end

  describe ".category" do
    it "is :workspace_activity" do
      expect(described_class.category_name).to eq "workspace_activity"
    end
  end

  # Spec case 1: Recipient resolution returns added_user + owners-excluding-added-user, deduped.
  describe "recipient resolution" do
    it "returns the added user plus all workspace owners (deduped, no double-up if added user is already an owner)" do
      # Use `build` + evaluate the resolver directly — this isolates the
      # resolver-under-test from the `after_create_commit` side effect path.
      membership = build(:membership, user: added_user, workspace: workspace, role: member_role)
      membership.save!
      event = described_class.with(record: membership)
      recipients = event.send(:evaluate_recipients)
      expect(recipients).to match_array([ added_user, owner_user_a, owner_user_b ])
    end

    it "deduplicates when the added user is themselves an owner of the workspace" do
      # Edge case: simulate "added user is already an owner" by passing an
      # existing owner's membership through the resolver. The candidate list
      # would be [owner_user_a, owner_user_a, owner_user_b] without dedup.
      event = described_class.with(record: owner_a_membership)
      recipients = event.send(:evaluate_recipients)
      expect(recipients.count(owner_user_a)).to eq 1
      expect(recipients).to match_array([ owner_user_a, owner_user_b ])
    end
  end

  # Spec case 2: Added user receives one in-app notification.
  describe "added user — in-app" do
    it "creates exactly one Noticed::Notification row for the added user" do
      add_member!
      expect(
        Noticed::Notification.where(recipient: added_user, type: "#{described_class.name}::Notification").count
      ).to eq 1
    end
  end

  # Spec case 3: Added user receives one email job.
  describe "added user — email" do
    it "enqueues exactly one NotificationMailer.workspace_member_added targeting the added user" do
      added_user_email = added_user.email_address

      # v2 default prefs have workspace_activity on + email channel on at
      # "instant" frequency, so the happy path needs no explicit setup.
      # The opt-out side of this split is covered in the preference-gating
      # block below.

      expect {
        add_member!
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
      add_member!
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
      owner_emails = [ owner_user_a.email_address, owner_user_b.email_address ]
      add_member!
      drain_noticed_jobs
      perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob)

      delivered_to_owners = ActionMailer::Base.deliveries.flat_map(&:to) & owner_emails
      expect(delivered_to_owners).to be_empty
    end
  end

  # Spec case 6: Owner notifications remain unseen post-deliver (digest pipeline eligibility).
  describe "owner — digest eligibility" do
    it "leaves seen_at: nil on owner notifications post-deliver" do
      add_member!
      drain_noticed_jobs
      [ owner_user_a, owner_user_b ].each do |o|
        notif = Noticed::Notification.where(recipient: o, type: "#{described_class.name}::Notification").last
        expect(notif).not_to be_nil
        expect(notif.seen_at).to be_nil
      end
    end
  end

  # Spec case 7: Email gating — workspace_activity on (default) vs disabled.
  describe "preference gating — added user workspace_activity category" do
    it "enqueues the email under v2 defaults (workspace_activity on, email channel on)" do
      create(:user_preferences, user: added_user) # v2 default: everything on

      expect {
        add_member!
        drain_noticed_jobs
      }.to have_enqueued_mail(NotificationMailer, :workspace_member_added).once
    end

    it "does not enqueue the email when the added user disables the workspace_activity category" do
      prefs = create(:user_preferences, user: added_user)
      np = prefs.notification_preferences.deep_dup
      np["notification_types"]["workspace_activity"] = false
      prefs.update!(notification_preferences: np)

      expect {
        add_member!
        drain_noticed_jobs
      }.not_to have_enqueued_mail(NotificationMailer, :workspace_member_added)
    end

    it "defers the email when email frequency is non-instant (DigestMailerJob picks it up)" do
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
        add_member!
        drain_noticed_jobs
      }.not_to have_enqueued_mail(NotificationMailer, :workspace_member_added)
    end
  end

  # Spec case 8: Owner who disables the in_app channel does NOT get an in-app row;
  # other owners + added user are unaffected.
  describe "preference gating — owner in-app channel" do
    it "skips in-app for the disabling owner; other owners + added user still receive theirs" do
      prefs_a = create(:user_preferences, user: owner_user_a)
      delivery_methods = prefs_a.notification_preferences["delivery_methods"].deep_dup
      delivery_methods["in_app"]["enabled"] = false
      prefs_a.update!(notification_preferences:
        prefs_a.notification_preferences.merge("delivery_methods" => delivery_methods))

      add_member!

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
      prefs = create(:user_preferences, user: added_user)
      prefs.update!(notification_preferences:
        prefs.notification_preferences.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))

      expect {
        add_member!
        drain_noticed_jobs
      }.not_to have_enqueued_mail(NotificationMailer, :workspace_member_added)

      expect(Noticed::Notification.where(recipient: added_user,
                                          type: "#{described_class.name}::Notification").count).to eq 0
    end
  end

  # Spec case 10: Single noticed_events row per dispatch regardless of recipient count.
  describe "single event row" do
    it "creates exactly one Noticed::Event row per dispatch (even with multiple recipients)" do
      expect {
        add_member!
      }.to change { Noticed::Event.where(type: described_class.name).count }.by(1)
    end
  end

  describe "Membership#after_create_commit trigger" do
    it "fires the notifier when a new membership is created" do
      expect {
        add_member!
      }.to change { Noticed::Event.where(type: described_class.name).count }.by(1)
    end

    it "does not fire on subsequent updates to an existing membership" do
      m = add_member!
      expect {
        m.touch
      }.not_to change { Noticed::Event.where(type: described_class.name).count }
    end
  end
end

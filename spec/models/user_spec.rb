require "rails_helper"

# The core's examples; each trait's live beside it under spec/models/user/.
RSpec.describe User, type: :model do
  describe "validations" do
    it "requires an email address" do
      user = User.new(email_address: nil)
      expect(user).not_to be_valid
      expect(user.errors[:email_address]).to be_present
    end

    it "requires a unique email address" do
      create(:user, email_address: "test@example.com")
      duplicate = build(:user, email_address: "test@example.com")
      expect(duplicate).not_to be_valid
    end

    it "normalizes email to lowercase" do
      user = create(:user, email_address: "Test@Example.COM")
      expect(user.email_address).to eq("test@example.com")
    end
  end

  describe "associations" do
    it "has many sessions" do
      user = create(:user)
      session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
      expect(user.sessions).to include(session)
    end

    # #931: #workspaces ran through every membership, so a removed member still
    # reached the workspace through WorkspaceScoped and the switcher.
    it "drops a workspace from #workspaces once the membership is deactivated" do
      user = create(:user)
      workspace = create(:workspace)
      membership = create(:membership, user: user, workspace: workspace)

      expect(user.workspaces.reload).to include(workspace)

      membership.deactivate!

      expect(user.workspaces.reload).not_to include(workspace)
      expect(user.memberships.reload).to include(membership)
    end
  end

  describe "#full_name" do
    it "returns first and last name" do
      user = build(:user, first_name: "Jane", last_name: "Doe")
      expect(user.full_name).to eq("Jane Doe")
    end
  end

  describe "#initials" do
    it "returns first letters of first and last name" do
      user = build(:user, first_name: "Jane", last_name: "Doe")
      expect(user.initials).to eq("JD")
    end

    it "returns single initial when only first name" do
      user = build(:user, first_name: "Jane", last_name: "")
      expect(user.initials).to eq("J")
    end

    it "returns fallback when name is blank" do
      user = build(:user, first_name: "", last_name: "")
      expect(user.initials).to eq("?")
    end
  end

  describe "name validations" do
    it "requires first_name" do
      user = build(:user, first_name: nil)
      expect(user).not_to be_valid
      expect(user.errors[:first_name]).to be_present
    end

    it "limits first_name to 100 characters" do
      user = build(:user, first_name: "a" * 101)
      expect(user).not_to be_valid
      expect(user.errors[:first_name]).to be_present
    end

    it "requires last_name" do
      user = build(:user, last_name: nil)
      expect(user).not_to be_valid
      expect(user.errors[:last_name]).to be_present
    end

    it "limits last_name to 100 characters" do
      user = build(:user, last_name: "a" * 101)
      expect(user).not_to be_valid
      expect(user.errors[:last_name]).to be_present
    end
  end

  describe "email normalization" do
    it "strips whitespace from email" do
      user = create(:user, email_address: "  test@example.com  ")
      expect(user.email_address).to eq("test@example.com")
    end
  end

  describe "#unread_notification_breakdown" do
    let(:user) { create(:user) }
    # SignInFromNewDeviceNotifier requires :user_agent and :os params.
    let(:user_agent) { "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2) AppleWebKit/605.1.15" }
    let(:os) { "Macintosh" }

    it "returns an empty hash when there are no notifications" do
      expect(user.unread_notification_breakdown).to eq({})
    end

    it "returns an empty hash when all notifications are read" do
      PasswordChangedNotifier.with(record: user).deliver(user)
      user.notifications.update_all(read_at: Time.current)
      expect(user.unread_notification_breakdown).to eq({})
    end

    it "groups unread notifications by notifier event type with counts" do
      PasswordChangedNotifier.with(record: user).deliver(user)
      PasswordChangedNotifier.with(record: user, idempotency_key: "another").deliver(user)
      SignInFromNewDeviceNotifier.with(record: user, user_agent: user_agent, os: os).deliver(user)

      expect(user.unread_notification_breakdown).to eq(
        "PasswordChangedNotifier"     => 2,
        "SignInFromNewDeviceNotifier" => 1
      )
    end

    it "ignores read notifications when counting unread" do
      PasswordChangedNotifier.with(record: user).deliver(user)
      SignInFromNewDeviceNotifier.with(record: user, user_agent: user_agent, os: os).deliver(user)
      user.notifications.where(type: "PasswordChangedNotifier::Notification")
          .update_all(read_at: Time.current)

      expect(user.unread_notification_breakdown).to eq(
        "SignInFromNewDeviceNotifier" => 1
      )
    end
  end

  describe "#email_verification_pending?" do
    it "is true when the email authentication is unverified" do
      user = create(:user, :unverified_email)
      expect(user.email_verification_pending?).to be(true)
    end

    it "is false when the email authentication is verified" do
      user = create(:user, :unverified_email)
      user.authentications.email.first.update!(verified_at: Time.current)
      expect(user.email_verification_pending?).to be(false)
    end

    it "is false when there is no email authentication (e.g. OAuth-only)" do
      user = create(:user, :oauth_only)
      expect(user.email_verification_pending?).to be(false)
    end
  end

  describe "#webauthn_handle!" do
    it "lazily generates a stable opaque handle" do
      user = create(:user)
      handle = user.webauthn_handle!
      expect(handle).to be_present
      expect(user.webauthn_handle!).to eq(handle) # stable on second call
    end
  end

  describe "#destroy with invitation history (T23, #816)" do
    it "destroys sent invitations and blocks, and detaches accepted ones" do
      user = create(:user)
      workspace = create(:workspace)
      sent = create(:invitation, invitable: workspace, invited_by: user)
      create(:invitation_block, inviter: user, email: "b@example.com")
      accepted = create(:invitation, invitable: create(:workspace), invited_by: create(:user))
      accepted.accept!(user)

      expect { user.destroy! }.to change(Invitation, :count).by(-1)
      expect(InvitationBlock.where(inviter_id: user.id)).to be_empty
      expect(accepted.reload.accepted_by_id).to be_nil
      expect(Invitation.exists?(sent.id)).to be(false)
    end
  end

  describe "#destroy" do
    include ActiveSupport::Testing::TimeHelpers

    # Three deliveries, each in its own idempotency minute-bucket so noticed
    # does not dedup them into one row.
    def deliver_three_to(user)
      3.times do |i|
        travel_to(Time.current + (i + 1).minutes) do
          PasswordChangedNotifier.with(record: user).deliver(user)
        end
      end
      expect(user.notifications.count).to eq(3)
    end

    it "removes the user's notification rows with a single DELETE (#817)" do
      user = create(:user)
      deliver_three_to(user)

      queries = count_queries_touching("noticed_notifications") { user.destroy! }

      expect(queries).to eq(1)
    end

    it "removes the user's pending challenges with the user" do
      user = create(:user)
      ReauthenticationChallenge.issue_for(user)
      WebauthnChallenge.store(challenge: "spec-challenge", purpose: "authentication", user: user)

      expect { user.destroy! }
        .to change(ReauthenticationChallenge, :count).by(-1)
        .and change(WebauthnChallenge, :count).by(-1)
    end

    it "refuses a user who created a project, and names what they still own" do
      user = create(:user)
      create(:project, created_by: user)

      expect(user.destroy).to be false
      expect(user.errors.details[:base]).to include(a_hash_including(error: :"restrict_dependent_destroy.has_many"))
      expect(user.reload).to be_persisted
    end

    it "refuses the creator of a join link the same way" do
      user = create(:user)
      create(:workspace_join_link, created_by: user)

      expect(user.destroy).to be false
      expect(user.errors.details[:base]).to include(a_hash_including(record: "created workspace join links"))
    end
  end

  describe "operator reach" do
    let(:user) { create(:user) }
    let!(:workspace) { create(:workspace) }
    let!(:suspended) { create(:workspace).tap(&:suspend!) }
    let!(:discarded) { create(:workspace).tap(&:discard!) }

    it "is not an operator by default and reaches no workspaces" do
      expect(user).not_to be_operator
      expect(user.operated_workspaces).to be_empty
      expect(user.operated_workspaces).to be_a(ActiveRecord::Relation)
    end

    it "reaches every kept workspace, suspended included, once granted" do
      Operatorship.grant!(user: user)

      expect(user.reload).to be_operator
      # `include`, not `contain_exactly`: under the default :personal preset,
      # `user`'s own onboarding workspace is also kept and legitimately in
      # scope here — operated_workspaces is instance-wide reach, not "every
      # workspace but mine".
      expect(user.operated_workspaces).to include(workspace, suspended)
      expect(user.operated_workspaces).not_to include(discarded)
    end

    it "loses reach when the operatorship is revoked" do
      Operatorship.grant!(user: user).revoke!

      expect(user.reload).not_to be_operator
      expect(user.operated_workspaces).to be_empty
    end
  end

  # The users half of the operations reach, one line for scoped operators (#1123).
  describe "#operated_users" do
    let(:user) { create(:user) }

    it "reaches nobody, as a relation, without an operatorship" do
      expect(user).not_to be_operator
      expect(user.operated_users).to be_empty
      expect(user.operated_users).to be_a(ActiveRecord::Relation)
    end

    it "reaches every user once granted, suspended included and itself among them" do
      suspended_user = create(:user).tap { |u| u.suspend!(by: user) }
      other = create(:user)
      Operatorship.grant!(user: user)

      expect(user.reload).to be_operator
      expect(user.operated_users).to include(user, other, suspended_user)
    end

    it "loses reach when the operatorship is revoked" do
      Operatorship.grant!(user: user).revoke!

      expect(user.reload).not_to be_operator
      expect(user.operated_users).to be_empty
    end
  end

  describe "#granted_operatorships" do
    it "carries every operatorship a user has granted, keyed by granted_by_id" do
      granter = create(:user)
      first_grant = Operatorship.grant!(user: create(:user), granted_by: granter)
      second_grant = Operatorship.grant!(user: create(:user), granted_by: granter)

      expect(granter.granted_operatorships).to contain_exactly(first_grant, second_grant)
      expect(granter.granted_operatorships.pluck(:granted_by_id).uniq).to eq([ granter.id ])
    end
  end

  describe "#unlock!" do
    it "clears the lockout and writes an admin-visibility row naming the operator" do
      operator = create(:user)
      user = create(:user)
      5.times { user.register_failed_login! }
      expect(user.reload).to be_locked

      expect(user.unlock!(by: operator)).to eq(:unlocked)

      expect(user.reload.locked_at).to be_nil
      expect(user.failed_login_attempts).to eq(0)
      row = ActivityLog.find_by!(action: "user.unlocked", trackable: user)
      expect(row.actor).to eq(operator)
      expect(row.visibility).to eq("admin")
    end

    it "returns :not_locked and writes no row when the account isn't locked" do
      user = create(:user)
      operator = create(:user)
      expect {
        expect(user.unlock!(by: operator)).to eq(:not_locked)
      }.not_to change(ActivityLog, :count)
    end

    it "accepts a nil actor, the rake shape" do
      user = create(:user)
      5.times { user.register_failed_login! }
      expect(user.unlock!(by: nil)).to eq(:unlocked)
      expect(ActivityLog.find_by!(action: "user.unlocked", trackable: user).actor).to be_nil
    end

    it "a successful login clears the same counter but writes no row (the Session row is the record)" do
      user = create(:user)
      3.times { user.register_failed_login! }

      expect { user.register_successful_login! }.not_to change(ActivityLog, :count)

      expect(user.reload.failed_login_attempts).to eq(0)
      expect(user.locked_at).to be_nil
    end
  end

  describe "#suspend!" do
    it "suspends, destroys sessions, and writes an admin-visibility row naming the operator, leaving memberships intact" do
      operator = create(:user)
      user = create(:user)
      workspace = create(:workspace)
      create(:membership, :owner, user: user, workspace: workspace)
      user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")

      expect {
        expect(user.suspend!(by: operator)).to eq(:suspended)
      }.not_to change { user.memberships.kept.count }

      expect(user.reload).to be_suspended
      expect(user.sessions.count).to eq(0)
      row = ActivityLog.find_by!(action: "user.suspended", trackable: user)
      expect(row.actor).to eq(operator)
      expect(row.visibility).to eq("admin")
    end

    it "is a no-op on a second call and does not bump suspended_at" do
      user = create(:user, :suspended)
      operator = create(:user)
      suspended_at = user.suspended_at

      expect {
        expect(user.suspend!(by: operator)).to eq(:already_suspended)
      }.not_to change(ActivityLog, :count)

      expect(user.reload.suspended_at).to eq(suspended_at)
    end

    it "accepts a nil actor, the rake shape" do
      user = create(:user)
      expect(user.suspend!(by: nil)).to eq(:suspended)
      expect(ActivityLog.find_by!(action: "user.suspended", trackable: user).actor).to be_nil
    end

    it "rolls back the suspension when the audit write fails, leaving the session alive" do
      user = create(:user)
      session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
      allow(ActivityLog).to receive(:create!).and_raise(StandardError, "boom")

      expect { user.suspend!(by: create(:user)) }.to raise_error(StandardError, "boom")

      expect(user.reload.suspended_at).to be_nil
      expect(Session.exists?(session.id)).to be true
    end
  end

  describe "#unsuspend!" do
    it "clears the suspension and writes an admin-visibility row naming the operator" do
      operator = create(:user)
      user = create(:user, :suspended)

      expect(user.unsuspend!(by: operator)).to eq(:unsuspended)

      expect(user.reload).not_to be_suspended
      row = ActivityLog.find_by!(action: "user.unsuspended", trackable: user)
      expect(row.actor).to eq(operator)
      expect(row.visibility).to eq("admin")
    end

    it "returns :not_suspended and writes no row when the account isn't suspended" do
      user = create(:user)
      operator = create(:user)
      expect {
        expect(user.unsuspend!(by: operator)).to eq(:not_suspended)
      }.not_to change(ActivityLog, :count)
    end

    it "accepts a nil actor, the rake shape" do
      user = create(:user, :suspended)
      expect(user.unsuspend!(by: nil)).to eq(:unsuspended)
      expect(ActivityLog.find_by!(action: "user.unsuspended", trackable: user).actor).to be_nil
    end
  end
end

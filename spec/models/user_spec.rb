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
  end
end

require "rails_helper"

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
      expect(User.reflect_on_association(:sessions).macro).to eq(:has_many)
    end
  end

  describe "personal workspace" do
    it "creates a personal workspace on sign-up" do
      user = create(:user)
      expect(user.workspaces.count).to eq(1)
      expect(user.workspaces.first.name).to include(user.first_name)
    end

    it "assigns owner role to personal workspace" do
      user = create(:user)
      membership = user.memberships.first
      expect(membership.role.slug).to eq("owner")
    end
  end

  describe "account locking" do
    let(:user) { create(:user) }

    it "locks after 5 failed attempts" do
      5.times { user.register_failed_login! }
      expect(user.reload).to be_locked
    end

    it "does not lock after 4 failed attempts" do
      4.times { user.register_failed_login! }
      expect(user.reload).not_to be_locked
    end

    it "auto-unlocks after 1 hour" do
      user.update!(locked_at: 61.minutes.ago, failed_login_attempts: 5)
      expect(user).not_to be_locked
    end

    it "resets failed attempts on successful login" do
      3.times { user.register_failed_login! }
      user.register_successful_login!
      expect(user.reload.failed_login_attempts).to eq(0)
    end
  end
end

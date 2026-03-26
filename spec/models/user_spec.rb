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

  describe "#full_name" do
    it "returns first and last name" do
      user = build(:user, first_name: "Jane", last_name: "Doe")
      expect(user.full_name).to eq("Jane Doe")
    end
  end

  describe "name validations" do
    it "requires first_name" do
      user = build(:user, first_name: nil)
      expect(user).not_to be_valid
      expect(user.errors[:first_name]).to include("can't be blank")
    end

    it "limits first_name to 100 characters" do
      user = build(:user, first_name: "a" * 101)
      expect(user).not_to be_valid
      expect(user.errors[:first_name]).to be_present
    end

    it "requires last_name" do
      user = build(:user, last_name: nil)
      expect(user).not_to be_valid
      expect(user.errors[:last_name]).to include("can't be blank")
    end

    it "limits last_name to 100 characters" do
      user = build(:user, last_name: "a" * 101)
      expect(user).not_to be_valid
      expect(user.errors[:last_name]).to be_present
    end
  end

  describe "password validations" do
    it "requires minimum 12 characters" do
      user = build(:user, password: "Short1!aaa")
      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it "accepts 12+ character password" do
      user = build(:user, password: "ValidP@ssw0rd!")
      expect(user).to be_valid
    end
  end

  describe "email normalization" do
    it "strips whitespace from email" do
      user = create(:user, email_address: "  test@example.com  ")
      expect(user.email_address).to eq("test@example.com")
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

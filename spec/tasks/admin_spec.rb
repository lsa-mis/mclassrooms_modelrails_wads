require "rails_helper"
require "rake"

RSpec.describe "Admin rake tasks" do
  before(:all) do
    Rails.application.load_tasks
  end

  describe "users:unlock" do
    it "unlocks a locked user" do
      user = create(:user)
      5.times { user.register_failed_login! }
      expect(user.reload).to be_locked

      Rake::Task["users:unlock"].reenable
      Rake::Task["users:unlock"].invoke(user.email_address)

      expect(user.reload).not_to be_locked
      expect(user.reload.failed_login_attempts).to eq(0)
    end
  end

  describe "users:verify" do
    it "verifies an unverified email" do
      user = create(:user)
      auth = user.authentications.create!(provider: "email", uid: user.email_address)
      auth.generate_verification_token!
      expect(auth).not_to be_verified

      Rake::Task["users:verify"].reenable
      Rake::Task["users:verify"].invoke(user.email_address)

      expect(auth.reload).to be_verified
    end
  end

  describe "users:suspend" do
    it "destroys sessions and discards memberships" do
      user = create(:user)
      workspace = create(:workspace)
      create(:membership, :owner, user: user, workspace: workspace)
      create(:membership, :owner, workspace: workspace)
      user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")

      Rake::Task["users:suspend"].reenable
      Rake::Task["users:suspend"].invoke(user.email_address)

      expect(user.sessions.count).to eq(0)
      expect(user.memberships.kept.count).to eq(0)
    end
  end
end

require "rails_helper"
require "rake"

RSpec.describe "Admin rake tasks" do
  before(:all) { RakeTasks.load_once }

  describe "users:unlock" do
    it "unlocks a locked user" do
      user = create(:user)
      5.times { user.register_failed_login! }
      expect(user.reload).to be_locked

      Rake::Task["users:unlock"].reenable
      expect { Rake::Task["users:unlock"].invoke(user.email_address) }
        .to output(/Unlocked/).to_stdout

      expect(user.reload).not_to be_locked
      expect(user.reload.failed_login_attempts).to eq(0)
    end

    it "reports a not-locked account as a no-op rather than an error" do
      user = create(:user)

      Rake::Task["users:unlock"].reenable
      expect { Rake::Task["users:unlock"].invoke(user.email_address) }
        .to output(/is not locked/).to_stdout
    end
  end

  describe "users:verify" do
    it "verifies an unverified email" do
      user = create(:user, :unverified_email)
      auth = user.authentications.sole
      expect(auth).not_to be_verified

      Rake::Task["users:verify"].reenable
      Rake::Task["users:verify"].invoke(user.email_address)

      expect(auth.reload).to be_verified
    end
  end

  describe "users:suspend" do
    it "destroys sessions, blocks sign-in, and leaves memberships untouched" do
      user = create(:user)
      workspace = create(:workspace)
      create(:membership, :owner, user: user, workspace: workspace)
      create(:membership, :owner, workspace: workspace)
      user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")

      Rake::Task["users:suspend"].reenable
      expect {
        expect { Rake::Task["users:suspend"].invoke(user.email_address) }
          .to output(/Suspended/).to_stdout
      }.not_to change { user.memberships.kept.count }

      expect(user.reload).to be_suspended
      expect(user.sessions.count).to eq(0)
    end

    it "reports a repeat suspend as a no-op rather than an error" do
      user = create(:user, :suspended)

      Rake::Task["users:suspend"].reenable
      expect { Rake::Task["users:suspend"].invoke(user.email_address) }
        .to output(/already suspended/).to_stdout
    end
  end

  describe "users:unsuspend" do
    it "restores sign-in" do
      user = create(:user, :suspended)

      Rake::Task["users:unsuspend"].reenable
      expect { Rake::Task["users:unsuspend"].invoke(user.email_address) }
        .to output(/Unsuspended/).to_stdout

      expect(user.reload).not_to be_suspended
    end

    it "reports a not-suspended account as a no-op rather than an error" do
      user = create(:user)

      Rake::Task["users:unsuspend"].reenable
      expect { Rake::Task["users:unsuspend"].invoke(user.email_address) }
        .to output(/is not suspended/).to_stdout
    end
  end

  describe "workspaces:suspend" do
    it "suspends the workspace by slug" do
      workspace = create(:workspace)

      Rake::Task["workspaces:suspend"].reenable
      Rake::Task["workspaces:suspend"].invoke(workspace.slug)

      expect(workspace.reload).to be_suspended
    end

    it "reports a repeat suspend as a no-op rather than an error" do
      workspace = create(:workspace).tap(&:suspend!)
      suspended_at = workspace.suspended_at

      Rake::Task["workspaces:suspend"].reenable
      expect { Rake::Task["workspaces:suspend"].invoke(workspace.slug) }
        .to output(/already suspended/).to_stdout

      expect(workspace.reload.suspended_at).to eq(suspended_at)
    end
  end

  describe "workspaces:unsuspend" do
    it "clears the suspension" do
      workspace = create(:workspace).tap(&:suspend!)

      Rake::Task["workspaces:unsuspend"].reenable
      Rake::Task["workspaces:unsuspend"].invoke(workspace.slug)

      expect(workspace.reload).not_to be_suspended
    end

    it "reports a repeat unsuspend as a no-op rather than an error" do
      workspace = create(:workspace)

      Rake::Task["workspaces:unsuspend"].reenable
      expect { Rake::Task["workspaces:unsuspend"].invoke(workspace.slug) }
        .to output(/is not suspended/).to_stdout

      expect(workspace.reload.suspended_at).to be_nil
    end
  end
end

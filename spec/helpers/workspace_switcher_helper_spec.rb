require "rails_helper"

RSpec.describe WorkspaceSwitcherHelper, type: :helper do
  # #931: the switcher listed a workspace the user had been removed from,
  # offering a chip that led straight into the refusal loop.
  describe "#switcher_workspaces" do
    let(:user) { create(:user) }

    before do
      allow(Current).to receive(:user).and_return(user)
      allow(Current).to receive(:workspace).and_return(nil)
    end

    # The helper eager-loads the chip's logo and role for the header render.
    # This example asserts membership state only and never renders, so Bullet's
    # unused-eager-loading check false-positives — same treatment as
    # spec/helpers/notifications_helper_spec.rb.
    around do |example|
      if defined?(Bullet) && Bullet.enable?
        original = Bullet.unused_eager_loading_enable?
        Bullet.unused_eager_loading_enable = false
        begin
          example.run
        ensure
          Bullet.unused_eager_loading_enable = original
        end
      else
        example.run
      end
    end

    it "omits a workspace whose membership was deactivated and keeps the active one" do
      active = create(:workspace, name: "Active Org")
      removed = create(:workspace, name: "Removed Org")
      create(:membership, :owner, user: user, workspace: active)
      create(:membership, user: user, workspace: removed).deactivate!

      expect(helper.switcher_workspaces).to include(active)
      expect(helper.switcher_workspaces).not_to include(removed)
    end
  end

  describe "#switcher_current_workspace" do
    # first_name pinned so the personal workspace ("Zed's Workspace") sorts
    # after the org workspaces in the alphabetical cold-start test below.
    let(:user) { create(:user, first_name: "Zed") }

    before do
      allow(Current).to receive(:user).and_return(user)
      allow(Current).to receive(:workspace).and_return(nil)
    end

    it "falls back to the most-recently-accessed workspace when neither an active workspace nor session memory exists" do
      recent = create(:workspace, name: "Recent Org")
      stale = create(:workspace, name: "Stale Org")
      create(:membership, :owner, user: user, workspace: recent, last_accessed_at: 1.minute.ago)
      create(:membership, :owner, user: user, workspace: stale, last_accessed_at: 1.week.ago)

      expect(helper.switcher_current_workspace).to eq(recent)
    end

    it "falls back to the alphabetically-first workspace when no membership has been accessed yet" do
      zeta = create(:workspace, name: "Zeta Org")
      acme = create(:workspace, name: "Acme Org")
      create(:membership, :owner, user: user, workspace: zeta)
      create(:membership, :owner, user: user, workspace: acme)
      user.memberships.update_all(last_accessed_at: nil)

      expect(helper.switcher_current_workspace).to eq(acme)
    end

    it "prefers the session-remembered workspace over recency" do
      remembered = create(:workspace, name: "Remembered Org")
      recent = create(:workspace, name: "Recent Org")
      create(:membership, :owner, user: user, workspace: remembered, last_accessed_at: 1.week.ago)
      create(:membership, :owner, user: user, workspace: recent, last_accessed_at: 1.minute.ago)
      session[:current_workspace_id] = remembered.id

      expect(helper.switcher_current_workspace).to eq(remembered)
    end
  end
end

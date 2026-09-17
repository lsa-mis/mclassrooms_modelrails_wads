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
end

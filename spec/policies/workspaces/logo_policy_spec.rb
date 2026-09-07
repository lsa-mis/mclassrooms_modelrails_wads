require "rails_helper"

# Same capability surface as ProfilePolicy (manage_settings): the picker is
# part of editing the workspace's identity.
RSpec.describe Workspaces::LogoPolicy do
  let(:workspace) { create(:workspace) }

  before { Current.workspace = workspace }

  describe "for owner" do
    let(:user) { create(:user) }
    before { create(:membership, :owner, user: user, workspace: workspace) }

    it "allows show" do
      expect(described_class.new(user, workspace).show?).to be true
    end
  end

  describe "for a plain member" do
    let(:user) { create(:user) }
    before { create(:membership, user: user, workspace: workspace) }

    it "denies show" do
      expect(described_class.new(user, workspace).show?).to be false
    end
  end
end

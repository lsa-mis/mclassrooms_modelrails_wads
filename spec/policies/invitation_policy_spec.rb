require "rails_helper"

RSpec.describe InvitationPolicy do
  let(:workspace) { create(:workspace) }
  let(:invitation) { create(:invitation, invitable: workspace) }

  before { Current.workspace = workspace }

  describe "for owner" do
    let(:user) { create(:user) }
    before { create(:membership, :owner, user: user, workspace: workspace) }

    it "allows index" do
      expect(described_class.new(user, invitation).index?).to be true
    end

    it "allows create" do
      expect(described_class.new(user, invitation).create?).to be true
    end

    it "allows destroy" do
      expect(described_class.new(user, invitation).destroy?).to be true
    end

    it "allows resend" do
      expect(described_class.new(user, invitation).resend?).to be true
    end
  end

  describe "for member" do
    let(:user) { create(:user) }
    before { create(:membership, user: user, workspace: workspace) }

    it "allows index" do
      expect(described_class.new(user, invitation).index?).to be true
    end

    it "denies create" do
      expect(described_class.new(user, invitation).create?).to be false
    end

    it "denies destroy" do
      expect(described_class.new(user, invitation).destroy?).to be false
    end
  end

  describe "for viewer" do
    let(:user) { create(:user) }
    let(:viewer_role) { Role.find_or_create_by!(slug: "viewer", workspace_id: nil) { |r| r.name = "Viewer" } }
    before { create(:membership, user: user, workspace: workspace, role: viewer_role) }

    it "allows index" do
      expect(described_class.new(user, invitation).index?).to be true
    end

    it "denies create" do
      expect(described_class.new(user, invitation).create?).to be false
    end
  end
end

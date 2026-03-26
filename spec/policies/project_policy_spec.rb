require "rails_helper"

RSpec.describe ProjectPolicy do
  let(:workspace) { create(:workspace) }
  let(:creator_user) { create(:user) }
  let(:editor_user) { create(:user) }
  let(:non_member_user) { create(:user) }
  let(:project) { create(:project, workspace: workspace, created_by: creator_user) }

  before do
    Current.workspace = workspace
    create(:membership, :owner, user: creator_user, workspace: workspace)
    create(:membership, user: editor_user, workspace: workspace)
    create(:membership, user: non_member_user, workspace: workspace)
    create(:project_membership, :creator, project: project, user: creator_user)
    create(:project_membership, project: project, user: editor_user)
  end

  describe "for project creator" do
    it "allows show" do
      expect(described_class.new(creator_user, project).show?).to be true
    end

    it "allows update" do
      expect(described_class.new(creator_user, project).update?).to be true
    end

    it "allows destroy" do
      expect(described_class.new(creator_user, project).destroy?).to be true
    end
  end

  describe "for project editor" do
    it "allows show" do
      expect(described_class.new(editor_user, project).show?).to be true
    end

    it "denies update" do
      expect(described_class.new(editor_user, project).update?).to be false
    end

    it "denies destroy" do
      expect(described_class.new(editor_user, project).destroy?).to be false
    end
  end

  describe "for workspace member not in project" do
    it "allows index" do
      expect(described_class.new(non_member_user, project).index?).to be true
    end

    it "denies show" do
      expect(described_class.new(non_member_user, project).show?).to be false
    end

    it "allows create" do
      expect(described_class.new(non_member_user, project).create?).to be true
    end
  end

  describe "workspace owner (not project member) can destroy" do
    let(:owner_user) { create(:user) }
    before { create(:membership, :owner, user: owner_user, workspace: workspace) }

    it "allows destroy via manage_workspace permission" do
      expect(described_class.new(owner_user, project).destroy?).to be true
    end
  end
end

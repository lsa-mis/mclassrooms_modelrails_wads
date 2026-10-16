require "rails_helper"

RSpec.describe CharacteristicPolicy do
  let(:workspace) { create(:workspace) }

  before { Current.workspace = workspace }

  def member_with_role(slug)
    user = create(:user)
    create(:membership, user: user, workspace: workspace, role: Role.system_default!(slug))
    user
  end

  let(:admin_user) { member_with_role("admin") }
  let(:viewer_user) { member_with_role("viewer") }
  let(:no_membership_user) { create(:user) }

  describe "#index?" do
    it "allows any signed-in user regardless of role" do
      expect(described_class.new(admin_user, :characteristic).index?).to be true
      expect(described_class.new(viewer_user, :characteristic).index?).to be true
      expect(described_class.new(no_membership_user, :characteristic).index?).to be true
    end

    it "denies a nil (signed-out) user" do
      expect(described_class.new(nil, :characteristic).index?).to be false
    end
  end

  describe "mutations" do
    it "denies create — no mutations this phase (ApplicationPolicy default-deny)" do
      expect(described_class.new(admin_user, :characteristic).create?).to be false
    end
  end
end

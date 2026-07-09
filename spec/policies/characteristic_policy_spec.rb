require "rails_helper"

# MiClassrooms Phase 3 Task 1 (spec D5): CharacteristicPolicy authorizes the
# characteristic glossary + filter data (Find a Room screen). It's headless —
# controllers call `authorize :characteristic, :glossary?` rather than
# authorizing a record — so `record` is just the :characteristic symbol.
# Any signed-in user (viewer+) may read; no mutations exist this phase.
RSpec.describe CharacteristicPolicy do
  let(:workspace) { create(:workspace) }

  before { Current.workspace = workspace }

  def membership_with(slug)
    user = create(:user)
    create(:membership, user: user, workspace: workspace, role: Role.system_default!(slug))
    user
  end

  let(:admin_user) { membership_with("admin") }
  let(:viewer_user) { membership_with("viewer") }
  let(:no_membership_user) { create(:user) }

  describe "#glossary?" do
    it "allows any signed-in user regardless of role" do
      expect(described_class.new(admin_user, :characteristic).glossary?).to be true
      expect(described_class.new(viewer_user, :characteristic).glossary?).to be true
      expect(described_class.new(no_membership_user, :characteristic).glossary?).to be true
    end

    it "denies a nil (signed-out) user" do
      expect(described_class.new(nil, :characteristic).glossary?).to be false
    end
  end

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

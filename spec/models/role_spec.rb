require "rails_helper"

RSpec.describe Role, type: :model do
  describe "validations" do
    it "requires a name" do
      role = build(:role, name: nil)
      expect(role).not_to be_valid
    end

    it "requires a slug" do
      role = build(:role, slug: nil)
      expect(role).not_to be_valid
    end

    it "enforces unique slug per workspace" do
      workspace = create(:workspace)
      create(:role, slug: "custom", workspace: workspace)
      duplicate = build(:role, slug: "custom", workspace: workspace)
      expect(duplicate).not_to be_valid
    end

    it "allows same slug in different workspaces" do
      create(:role, slug: "custom", workspace: create(:workspace))
      other = build(:role, slug: "custom", workspace: create(:workspace))
      expect(other).to be_valid
    end
  end

  describe "system defaults" do
    before { Rails.application.load_seed }

    it "seeds 4 default roles" do
      expect(Role.where(workspace_id: nil).count).to eq(4)
    end

    %w[owner admin member viewer].each do |slug|
      it "seeds #{slug} role" do
        expect(Role.find_by(slug: slug, workspace_id: nil)).to be_present
      end
    end

    it "seeds permissions for owner" do
      owner = Role.find_by(slug: "owner")
      expect(owner.permissions).to include("manage_workspace" => true)
    end
  end
end

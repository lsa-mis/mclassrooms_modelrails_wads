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

    describe "permissions shape" do
      it "accepts an empty hash" do
        expect(build(:role, permissions: {})).to be_valid
      end

      it "accepts valid string-key boolean-value hash" do
        role = build(:role, permissions: { "manage_workspace" => true, "custom_perm" => false })
        expect(role).to be_valid
      end

      it "rejects non-hash permissions" do
        role = build(:role, permissions: "invalid")
        expect(role).not_to be_valid
        expect(role.errors[:permissions]).to include("must be a hash")
      end

      it "rejects non-boolean values" do
        role = build(:role, permissions: { "manage_workspace" => "yes" })
        expect(role).not_to be_valid
        expect(role.errors[:permissions]).to include("values must be booleans")
      end

      it "coerces non-string keys to strings via JSON serialization" do
        role = build(:role, permissions: { 123 => true })
        expect(role).to be_valid
        expect(role.permissions.keys).to all(be_a(String))
      end
    end
  end

  describe "system defaults" do
    let!(:default_roles) do
      {
        owner:  { name: "Owner",  permissions: { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true } },
        admin:  { name: "Admin",  permissions: { manage_members: true, manage_projects: true, manage_settings: true } },
        member: { name: "Member", permissions: { manage_projects: true } },
        viewer: { name: "Viewer", permissions: {} }
      }.each do |slug, attrs|
        Role.find_or_create_by!(slug: slug.to_s, workspace_id: nil) do |r|
          r.name = attrs[:name]
          r.permissions = attrs[:permissions]
        end
      end
    end

    it "has 4 default roles" do
      expect(Role.where(workspace_id: nil).count).to eq(4)
    end

    %w[owner admin member viewer].each do |slug|
      it "has #{slug} role" do
        expect(Role.find_by(slug: slug, workspace_id: nil)).to be_present
      end
    end

    it "owner has manage_workspace permission" do
      owner = Role.find_by(slug: "owner")
      expect(owner.permissions).to include("manage_workspace" => true)
    end
  end
end

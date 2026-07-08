require "rails_helper"

RSpec.describe Workspace, type: :model do
  describe "validations" do
    it "requires a name" do
      workspace = build(:workspace, name: nil)
      expect(workspace).not_to be_valid
      expect(workspace.errors[:name]).to be_present
    end

    it "auto-deduplicates slugs for same name" do
      first = create(:workspace, name: "Acme Corp")
      second = create(:workspace, name: "Acme Corp")
      expect(first.slug).to eq("acme-corp")
      expect(second.slug).to eq("acme-corp-1")
    end

    it "rejects duplicate slugs at validation level" do
      create(:workspace, name: "Acme Corp")
      duplicate = build(:workspace, name: "Different Name")
      duplicate.slug = "acme-corp"
      expect(duplicate).not_to be_valid
    end
  end

  describe "slug generation" do
    it "generates slug from name" do
      workspace = create(:workspace, name: "Acme Corp")
      expect(workspace.slug).to eq("acme-corp")
    end

    it "uses slug for to_param" do
      workspace = create(:workspace, name: "Acme Corp")
      expect(workspace.to_param).to eq("acme-corp")
    end

    it "generates a fallback slug for non-Latin names" do
      workspace = create(:workspace, name: "日本語の名前")
      expect(workspace.slug).to be_present
      expect(workspace.slug).not_to be_blank
    end
  end

  describe "plan enum" do
    it "defaults to free" do
      workspace = Workspace.new
      expect(workspace.plan).to eq("free")
    end

    it "supports pro and enterprise" do
      expect(build(:workspace, plan: "pro")).to be_valid
      expect(build(:workspace, plan: "enterprise")).to be_valid
    end
  end

  describe "settings defaults" do
    it "defaults max_members to 5" do
      expect(Workspace.new.max_members).to eq(5)
    end
  end

  describe "Discardable" do
    let(:workspace) { create(:workspace) }

    it "can be discarded" do
      workspace.discard!
      expect(workspace).to be_discarded
    end

    it "is excluded from kept scope when discarded" do
      workspace.discard!
      expect(Workspace.kept).not_to include(workspace)
    end

    it "can be undiscarded" do
      workspace.discard!
      workspace.undiscard!
      expect(workspace).not_to be_discarded
    end
  end

  describe "#effective_roles" do
    it "returns system defaults and workspace-specific roles" do
      owner_role = Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
        r.name = "Owner"
        r.permissions = { manage_workspace: true }
      end
      workspace = create(:workspace)
      custom_role = Role.create!(name: "Custom", slug: "custom", workspace: workspace)
      roles = workspace.effective_roles
      expect(roles).to include(owner_role)
      expect(roles).to include(custom_role)
    end
  end

  describe "#owners" do
    let(:workspace) { create(:workspace) }
    let(:owner_role) do
      Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" }
    end
    let(:member_role) do
      Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" }
    end

    it "returns all kept users with owner role for the workspace" do
      owner_a = create(:user)
      owner_b = create(:user)
      member  = create(:user)
      create(:membership, user: owner_a, workspace: workspace, role: owner_role)
      create(:membership, user: owner_b, workspace: workspace, role: owner_role)
      create(:membership, user: member,  workspace: workspace, role: member_role)

      expect(workspace.owners).to match_array([ owner_a, owner_b ])
    end

    it "excludes discarded owner memberships" do
      owner_a = create(:user)
      owner_b = create(:user)
      create(:membership, user: owner_a, workspace: workspace, role: owner_role)
      m2 = create(:membership, user: owner_b, workspace: workspace, role: owner_role)
      m2.discard!

      expect(workspace.owners).to match_array([ owner_a ])
    end

    it "returns an empty collection when the workspace has no owner-role memberships" do
      member = create(:user)
      create(:membership, user: member, workspace: workspace, role: member_role)
      expect(workspace.owners).to be_empty
    end
  end

  describe "logo" do
    it "generates initials from name" do
      workspace = build(:workspace, name: "Acme Corp")
      expect(workspace.initials).to eq("AC")
    end

    it "limits initials to 2 characters" do
      workspace = build(:workspace, name: "The Big Company Name")
      expect(workspace.initials).to eq("TB")
    end
  end

  describe "name length" do
    it "limits name to 255 characters" do
      workspace = build(:workspace, name: "a" * 256)
      expect(workspace).not_to be_valid
    end
  end

  describe "max_members validation" do
    it "requires max_members to be positive" do
      workspace = build(:workspace, max_members: 0)
      expect(workspace).not_to be_valid
    end
  end

  describe "logo attachment" do
    let(:workspace) { create(:workspace) }

    it "accepts valid image content types" do
      %w[image/png image/jpeg image/gif image/webp].each do |content_type|
        workspace.logo.attach(io: StringIO.new("fake"), filename: "test.png", content_type: content_type)
        workspace.valid?
        expect(workspace.errors[:logo]).to be_empty, "Expected #{content_type} to be valid"
      end
    end

    it "rejects non-image content types" do
      workspace.logo.attach(io: StringIO.new("not an image"), filename: "doc.pdf", content_type: "application/pdf")
      expect(workspace).not_to be_valid
      expect(workspace.errors[:logo]).to be_present
    end

    it "rejects files over 5MB" do
      workspace.logo.attach(io: StringIO.new("x" * 6.megabytes), filename: "big.png", content_type: "image/png")
      expect(workspace).not_to be_valid
      expect(workspace.errors[:logo]).to be_present
    end
  end

  describe "logo_original attachment" do
    let(:workspace) { create(:workspace) }

    it "rejects non-image content types" do
      workspace.logo_original.attach(io: StringIO.new("not an image"), filename: "doc.pdf", content_type: "application/pdf")
      expect(workspace).not_to be_valid
      expect(workspace.errors[:logo_original]).to be_present
    end

    it "rejects files over 10MB (original can be larger than cropped)" do
      workspace.logo_original.attach(io: StringIO.new("x" * 11.megabytes), filename: "big.png", content_type: "image/png")
      expect(workspace).not_to be_valid
      expect(workspace.errors[:logo_original]).to be_present
    end
  end

  describe "logo_source" do
    it "defaults to initials" do
      workspace = create(:workspace)
      expect(workspace.logo_source).to eq("initials")
    end

    it "validates inclusion in upload and initials" do
      workspace = build(:workspace, logo_source: "upload")
      expect(workspace).to be_valid

      workspace.logo_source = "invalid"
      expect(workspace).not_to be_valid
    end
  end

  describe "#available_logo_sources" do
    it "returns upload and initials" do
      workspace = build(:workspace)
      expect(workspace.available_logo_sources).to eq(%w[upload initials])
    end
  end

  describe "primary_color (integer hue)" do
    it "defaults to 210 (blue)" do
      workspace = create(:workspace)
      expect(workspace.primary_color).to eq(210)
    end

    it "validates inclusion in 0..360" do
      workspace = build(:workspace, primary_color: 180)
      expect(workspace).to be_valid

      workspace.primary_color = -1
      expect(workspace).not_to be_valid

      workspace.primary_color = 361
      expect(workspace).not_to be_valid
    end

    it "allows nil" do
      workspace = build(:workspace, primary_color: nil)
      expect(workspace).to be_valid
    end
  end

  describe "join_policy" do
    it "defaults to 'invite'" do
      workspace = create(:workspace)
      expect(workspace.join_policy).to eq("invite")
      expect(workspace).to be_invite
    end

    it "can be set to 'open_link' when the instance permits it" do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
      workspace = build(:workspace, join_policy: "open_link", personal: false)
      expect(workspace).to be_valid
      expect(workspace).to be_open_link
    end
  end

  describe "#open_join?" do
    before { allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link]) }

    it "is true for an org workspace with join_policy 'open_link' when instance permits it" do
      workspace = build(:workspace, join_policy: "open_link", personal: false)
      expect(workspace).to be_open_join
    end

    it "is false on a personal workspace, regardless of policy (hard guard)" do
      # Build without validation so we can simulate a malformed row reaching the predicate.
      workspace = build(:workspace, personal: true)
      workspace.join_policy = "open_link"
      expect(workspace).not_to be_open_join
    end

    it "is false when the instance allowlist excludes :open_link" do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite])
      workspace = build(:workspace, personal: false)
      workspace.join_policy = "open_link"
      expect(workspace).not_to be_open_join
    end

    it "is false for invite policy" do
      workspace = build(:workspace, join_policy: "invite", personal: false)
      expect(workspace).not_to be_open_join
    end
  end

  describe "personal-workspace hard guard validation" do
    it "rejects join_policy 'open_link' on a personal workspace" do
      workspace = build(:workspace, personal: true, join_policy: "open_link")
      expect(workspace).not_to be_valid
      expect(workspace.errors[:join_policy]).to be_present
    end

    it "permits join_policy 'invite' on a personal workspace" do
      workspace = build(:workspace, personal: true, join_policy: "invite")
      expect(workspace).to be_valid
    end
  end

  describe "instance allowlist validation" do
    it "rejects setting join_policy to a strategy the instance doesn't permit" do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite])
      workspace = build(:workspace, personal: false, join_policy: "open_link")
      expect(workspace).not_to be_valid
      expect(workspace.errors[:join_policy]).to include(/not permitted/i)
    end

    it "permits setting join_policy to a strategy in the allowlist" do
      allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
      workspace = build(:workspace, personal: false, join_policy: "open_link")
      expect(workspace).to be_valid
    end
  end

  # Single membership-grant entry point — extracted from Invitation so the
  # open-link self-join path can share the same lock + capacity + discarded-
  # reactivation + role-reconciliation logic.
  describe "#admit" do
    let(:workspace) { create(:workspace, max_members: 3, personal: false) }
    let(:user) { create(:user) }
    let!(:owner_role) {
      Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r|
        r.name = "Owner"
        r.permissions = { manage_workspace: true, manage_members: true, manage_settings: true }
      }
    }
    let!(:member_role) {
      Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r|
        r.name = "Member"
        r.permissions = {}
      }
    }

    it "creates a membership for a new user at the specified role" do
      expect {
        workspace.admit(user, role: member_role)
      }.to change(workspace.memberships, :count).by(1)

      expect(workspace.memberships.find_by!(user: user).role).to eq(member_role)
    end

    it "reactivates a discarded membership without overwriting its role" do
      # Seed the workspace with an Owner so deactivating doesn't violate
      # "must keep at least one owner" rules — and create a regular member
      # to deactivate as the test subject.
      other_owner = create(:user)
      workspace.memberships.create!(user: other_owner, role: owner_role)
      discarded = workspace.memberships.create!(user: user, role: member_role)
      discarded.deactivate!

      expect {
        workspace.admit(user, role: member_role)
      }.not_to change(workspace.memberships, :count)

      expect(discarded.reload).not_to be_discarded
    end

    it "raises RecordInvalid when the workspace is at capacity" do
      # Fill the workspace to max_members.
      workspace.update!(max_members: 1)
      workspace.memberships.create!(user: create(:user), role: owner_role)

      expect {
        workspace.admit(user, role: member_role)
      }.to raise_error(ActiveRecord::RecordInvalid, /capacity/i)
    end

    context "when user is already a kept member" do
      before { workspace.memberships.create!(user: user, role: member_role) }

      it "raises under :personal (duplicate-accept error)" do
        expect {
          workspace.admit(user, role: owner_role)
        }.to raise_error(ActiveRecord::RecordInvalid, /already a member/i)
      end

      context "under :shared posture" do
        before do
          allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
          allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(workspace.slug)
        end

        it "updates the role when it differs (placeholder reconciliation)" do
          expect {
            workspace.admit(user, role: owner_role)
          }.not_to raise_error

          expect(workspace.memberships.find_by!(user: user).role).to eq(owner_role)
        end

        it "no-ops when the role matches" do
          expect { workspace.admit(user, role: member_role) }.not_to raise_error
        end
      end
    end
  end
end

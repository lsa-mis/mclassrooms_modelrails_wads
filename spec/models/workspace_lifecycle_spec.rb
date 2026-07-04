require "rails_helper"

RSpec.describe Workspace, type: :model do
  let(:workspace) { create(:workspace) }

  describe "#status" do
    it "is :active with no lifecycle timestamps" do
      expect(workspace.status).to eq(:active)
    end

    it "is :archived when archived" do
      workspace.archive!
      expect(workspace.status).to eq(:archived)
    end

    it "is :suspended when suspended, taking precedence over archived" do
      workspace.archive!
      workspace.suspend!
      expect(workspace.status).to eq(:suspended)
    end

    it "is :discarded with highest precedence" do
      workspace.archive!
      workspace.discard!
      workspace.suspend!
      expect(workspace.status).to eq(:discarded)
    end
  end

  describe "guarded mutators" do
    it "blocks archive! while suspended" do
      workspace.suspend!
      expect { workspace.archive! }.to raise_error(Suspendable::SuspendedError)
      expect(workspace.reload.archived_at).to be_nil
    end

    it "blocks unarchive! while suspended (real transition attempt)" do
      workspace.archive!
      workspace.suspend!
      expect { workspace.unarchive! }.to raise_error(Suspendable::SuspendedError)
      expect(workspace.reload).to be_archived
    end

    it "blocks discard! while suspended" do
      workspace.suspend!
      expect { workspace.discard! }.to raise_error(Suspendable::SuspendedError)
      expect(workspace.reload).not_to be_discarded
    end

    it "does not raise on an idempotent archive! of an already-archived locked workspace" do
      workspace.archive!
      workspace.suspend!
      expect { workspace.archive! }.not_to raise_error
    end

    it "blocks admit while suspended" do
      member_role = Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r|
        r.name = "Member"
        r.permissions = { manage_projects: true }
      }
      user = create(:user)
      workspace.suspend!

      expect { workspace.admit(user, role: member_role) }.to raise_error(Workspace::NotAdmittableError)
      expect(workspace.memberships.find_by(user: user)).to be_nil
    end
  end

  describe "idempotency" do
    it "archives once: second call keeps the original timestamp and fires no callbacks" do
      workspace.archive!
      original = workspace.reload.archived_at
      expect { travel_to(1.hour.from_now) { workspace.archive! } }
        .not_to change { ActivityLog.count }
      expect(workspace.reload.archived_at).to eq(original)
    end

    it "discards once: second call fires no callbacks" do
      workspace.discard!
      expect { workspace.discard! }.not_to change { ActivityLog.count }
    end
  end

  describe "cascades" do
    let!(:project) { create(:project, workspace: workspace) }

    it "archive! does NOT touch project rows (no archive cascade)" do
      workspace.archive!
      expect(project.reload.archived_at).to be_nil
    end

    it "discard! still cascades to kept projects (unchanged)" do
      workspace.discard!
      expect(project.reload).to be_discarded
    end
  end

  describe "#home?" do
    it "is true for a personal workspace" do
      expect(create(:workspace, personal: true).home?).to be(true)
    end

    it "is false for an ordinary workspace under the default posture" do
      expect(create(:workspace, personal: false).home?).to be(false)
    end

    it "is true for the configured shared workspace under the :shared posture" do
      allow(TenancyConfig).to receive(:shared?).and_return(true)
      allow(TenancyConfig).to receive(:shared_workspace_slug).and_return("hq")
      expect(create(:workspace, slug: "hq", personal: false).home?).to be(true)
    end

    it "is false for a non-shared workspace even under the :shared posture" do
      allow(TenancyConfig).to receive(:shared?).and_return(true)
      allow(TenancyConfig).to receive(:shared_workspace_slug).and_return("hq")
      expect(create(:workspace, slug: "not-hq", personal: false).home?).to be(false)
    end
  end

  describe "home-workspace mutator guards" do
    let(:home) { create(:workspace, personal: true) }

    it "raises HomeWorkspaceError on archive!" do
      expect { home.archive! }.to raise_error(Workspace::HomeWorkspaceError)
      expect(home.reload.archived_at).to be_nil
    end

    it "raises HomeWorkspaceError on discard!" do
      expect { home.discard! }.to raise_error(Workspace::HomeWorkspaceError)
      expect(home.reload).not_to be_discarded
    end
  end

  describe "#admittable?" do
    let(:workspace) { create(:workspace) }

    it "is true only when active (kept, not archived, not suspended)" do
      expect(workspace.admittable?).to be(true)
    end

    it "is false when archived" do
      workspace.archive!
      expect(workspace.admittable?).to be(false)
    end

    it "is false when suspended" do
      workspace.suspend!
      expect(workspace.admittable?).to be(false)
    end

    it "is false when discarded" do
      workspace.discard!
      expect(workspace.admittable?).to be(false)
    end
  end

  describe "#admit admittability guard" do
    let(:workspace) { create(:workspace) }
    let(:role) { Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" } }
    let(:joiner) { create(:user) }

    it "raises NotAdmittableError when the workspace is archived" do
      workspace.archive!
      expect { workspace.admit(joiner, role: role) }.to raise_error(Workspace::NotAdmittableError)
      expect(workspace.reload.memberships.where(user: joiner)).to be_empty
    end

    it "raises NotAdmittableError when the workspace is suspended" do
      workspace.suspend!
      expect { workspace.admit(joiner, role: role) }.to raise_error(Workspace::NotAdmittableError)
    end

    it "admits normally into an active workspace" do
      expect { workspace.admit(joiner, role: role) }.to change { workspace.memberships.kept.count }.by(1)
    end
  end
end

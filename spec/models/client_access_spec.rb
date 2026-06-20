require "rails_helper"

RSpec.describe ClientAccess, type: :model do
  it "is valid with a company name on a clientside-enabled project" do
    access = build(:client_access)
    expect(access).to be_valid
  end

  it "requires a company name" do
    access = build(:client_access, company_name: "")
    expect(access).not_to be_valid
    expect(access.errors[:company_name]).to be_present
  end

  it "is unique per (project, user)" do
    existing = create(:client_access)
    dup = build(:client_access, project: existing.project, user: existing.user)
    expect(dup).not_to be_valid
  end

  it "cannot be created when the project's Clientside is disabled" do
    project = create(:project, clientside_enabled: false)
    access = build(:client_access, project: project)
    expect(access).not_to be_valid
    expect(access.errors[:base]).to be_present
  end

  it "supports soft-deletion via Discardable" do
    access = create(:client_access)
    access.discard!
    expect(access).to be_discarded
    expect(ClientAccess.kept).not_to include(access)
  end

  it "does not consume a workspace member seat" do
    project = create(:project, clientside_enabled: true)
    workspace = project.workspace
    before = workspace.memberships.kept.count
    client = create(:user)
    described_class.create!(project: project, user: client, company_name: "BigCo")
    expect(workspace.memberships.kept.count).to eq(before)
    expect(workspace.users).not_to include(client)
  end
end

require "rails_helper"

# MiClassrooms Phase 5 Task 1 (spec D5, Brief §14.1): RoleResolver is the
# single role/scope abstraction every Pundit policy consults. `RoleResolver`
# itself is the grant object — `.for(user)` builds one from the CURRENT
# workspace's kept membership plus the user's EditorAssignments, read fresh
# from the database on every call (never session-cached — fixes Brief §11.1).
#
# Roles are matched on Role#slug (the stable identifier Role.system_default!
# keys on — see app/models/role.rb and TestLoginsController#grant_test_role),
# not on Role#name (the display label), so a fork that localizes/renames the
# display name doesn't silently break admin detection.
RSpec.describe RoleResolver do
  let(:workspace) { create(:workspace) }
  let(:unit) { create(:unit) }
  let(:user) { create(:user) }

  before { Current.workspace = workspace }

  def membership_with(slug)
    create(:membership, user: user, workspace: workspace, role: Role.system_default!(slug))
  end

  it "returns a non-viewer null grant for nil user" do
    grant = described_class.for(nil)
    expect([ grant.admin?, grant.viewer?, grant.editor? ]).to all(be false)
  end

  it "is viewer-only for a kept membership with no assignments" do
    membership_with(:viewer)
    grant = described_class.for(user)
    expect([ grant.viewer?, grant.editor?, grant.admin? ]).to eq([ true, false, false ])
  end

  it "is admin for the admin and owner role slugs" do
    membership_with(:admin)
    expect(described_class.for(user).admin?).to be true
  end

  it "is editor with unit ids when EditorAssignments exist" do
    membership_with(:viewer)
    create(:editor_assignment, user: user, unit: unit)
    grant = described_class.for(user)
    expect(grant.editor?).to be true
    expect(grant.editor_unit_ids).to eq([ unit.id ])
  end

  it "nullifies editor grants when the membership is discarded" do
    membership_with(:viewer).discard!
    create(:editor_assignment, user: user, unit: unit)
    expect(described_class.for(user).editor?).to be false
  end

  describe "#can_edit_room?" do
    before do
      membership_with(:viewer)
      create(:editor_assignment, user: user, unit: unit)
    end

    it "is true only for rooms in an assigned unit" do
      grant = described_class.for(user)
      expect(grant.can_edit_room?(build(:room, unit: unit))).to be true
      expect(grant.can_edit_room?(build(:room, unit: create(:unit)))).to be false
    end

    it "is false for room.unit_id nil unless admin (blank department group => admin-only)" do
      expect(described_class.for(user).can_edit_room?(build(:room, unit: nil))).to be false
      admin = create(:user)
      create(:membership, user: admin, workspace: workspace, role: Role.system_default!(:admin))
      expect(described_class.for(admin).can_edit_room?(build(:room, unit: nil))).to be true
    end
  end

  it "reads the database on every call (no caching across grants)" do
    membership_with(:viewer)
    expect(described_class.for(user).editor?).to be false
    create(:editor_assignment, user: user, unit: unit)
    expect(described_class.for(user).editor?).to be true
  end
end

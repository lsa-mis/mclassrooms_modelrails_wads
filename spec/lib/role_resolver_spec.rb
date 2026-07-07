require "rails_helper"

# MiClassrooms Phase 0 Task 9: RoleResolver is the single role/scope
# abstraction every future Pundit policy consults (spec D5). This is a
# skeleton — admin/viewer are real, editor is stubbed (always false / empty)
# because EditorAssignment doesn't exist until phase 5.
#
# Roles are matched on Role#slug (the stable identifier Role.system_default!
# keys on — see app/models/role.rb and TestLoginsController#grant_test_role),
# not on Role#name (the display label), so a fork that localizes/renames the
# display name doesn't silently break admin detection.
RSpec.describe RoleResolver do
  let(:workspace) { create(:workspace) }
  let(:user) { create(:user) }

  # RoleResolver reuses TenancyConfig.shared_workspace rather than
  # re-resolving the workspace itself; stubbing it here — rather than flipping
  # the :shared onboarding posture — keeps these specs independent of which
  # tenancy preset the suite happens to be running under.
  before do
    allow(TenancyConfig).to receive(:shared_workspace).and_return(workspace)
  end

  def membership_with(slug)
    create(:membership, user: user, workspace: workspace, role: Role.system_default!(slug))
  end

  describe ".for" do
    it "grants admin? true for an Admin-role membership" do
      membership_with("admin")

      expect(described_class.for(user).admin?).to be(true)
    end

    it "grants admin? true for an Owner-role membership" do
      membership_with("owner")

      expect(described_class.for(user).admin?).to be(true)
    end

    it "grants viewer? true and admin? false for a Viewer-role membership" do
      membership_with("viewer")

      grant = described_class.for(user)
      expect(grant.viewer?).to be(true)
      expect(grant.admin?).to be(false)
    end

    it "grants viewer? false for a discarded membership" do
      membership = membership_with("viewer")
      membership.discard!

      grant = described_class.for(user)
      expect(grant.viewer?).to be(false)
      expect(grant.admin?).to be(false)
    end

    it "grants nothing when the user has no membership in the shared workspace" do
      grant = described_class.for(user)

      expect(grant.admin?).to be(false)
      expect(grant.viewer?).to be(false)
    end

    it "grants nothing when there is no shared workspace configured" do
      allow(TenancyConfig).to receive(:shared_workspace).and_return(nil)

      grant = described_class.for(user)

      expect(grant.admin?).to be(false)
      expect(grant.viewer?).to be(false)
    end

    it "is editor? false with empty editor_unit_ids for everyone, including admins (phase 5 stub)" do
      membership_with("admin")

      grant = described_class.for(user)
      expect(grant.editor?).to be(false)
      expect(grant.editor_unit_ids).to eq([])
    end

    it "performs a fresh DB read on every call — the grant is not memoized" do
      membership = membership_with("viewer")
      expect(described_class.for(user).admin?).to be(false)

      membership.update!(role: Role.system_default!("admin"))

      expect(described_class.for(user).admin?).to be(true)
    end
  end

  describe "#can_edit_room?" do
    # Rooms don't exist yet (phase 5). Duck-type the contract RoleResolver
    # depends on — anything responding to #unit_id — with a plain Struct
    # rather than reaching for a not-yet-existing Room model.
    let(:room_class) { Struct.new(:unit_id) }

    it "is true for admins regardless of the room's unit" do
      membership_with("admin")
      grant = described_class.for(user)

      expect(grant.can_edit_room?(room_class.new(42))).to be(true)
    end

    it "is false for non-admins even when the unit would match (editor stubbed empty)" do
      membership_with("viewer")
      grant = described_class.for(user)

      expect(grant.can_edit_room?(room_class.new(42))).to be(false)
    end

    it "is false for a non-admin grant when the room has no unit_id" do
      grant = described_class.for(user) # no membership at all -> admin? false

      expect(grant.can_edit_room?(room_class.new(nil))).to be(false)
    end
  end
end

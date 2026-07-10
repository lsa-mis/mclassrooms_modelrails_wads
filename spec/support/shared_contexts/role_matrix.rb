# MiClassrooms Phase 5 Task 3 (Brief §14.1): the four-actor fixture set every
# RoleResolver-driven policy matrix spec builds on — admin / editor-in-unit /
# editor-in-another-unit / plain viewer, plus the room fixtures that
# distinguish "in my unit" from "in someone else's unit" from "no unit at
# all" from "hidden". Shared across matrix specs so each one only has to
# supply its own MATRIX table, not re-derive this cast.
RSpec.shared_context "role matrix" do
  let(:workspace) { create(:workspace) }
  let(:unit) { create(:unit) }
  let(:other_unit) { create(:unit) }
  let(:admin_user) { create(:user) }
  let(:editor_user) { create(:user) }          # assigned to `unit`
  let(:other_editor_user) { create(:user) }    # assigned to `other_unit`
  let(:viewer_user) { create(:user) }
  let(:room_in_unit) { create(:room, unit: unit) }
  let(:room_other_unit) { create(:room, unit: other_unit) }
  let(:room_no_unit) { create(:room, unit: nil) }
  let(:hidden_room_in_unit) { create(:room, unit: unit, hidden_at: Time.current) }
  let(:building) { create(:building) }

  before do
    Current.workspace = workspace
    create(:membership, user: admin_user, workspace: workspace, role: Role.system_default!(:admin))
    [ editor_user, other_editor_user, viewer_user ].each do |u|
      create(:membership, user: u, workspace: workspace, role: Role.system_default!(:viewer))
    end
    create(:editor_assignment, user: editor_user, unit: unit)
    create(:editor_assignment, user: other_editor_user, unit: other_unit)
  end
end

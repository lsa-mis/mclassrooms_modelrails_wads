require "rails_helper"

# MiClassrooms Phase 5 Task 4 (Brief §14.1): EditorAssignmentPolicy — the
# admin console that grants/revokes editor claims on units is admin-only end
# to end. An editor managing editor assignments (their own or anyone else's)
# would be a privilege-escalation vector, so there is no editor carve-out
# here at all, unlike Note/Analytics/SyncRun.
RSpec.describe EditorAssignmentPolicy do
  include_context "role matrix"

  let(:editor_assignment_record) { create(:editor_assignment, unit: unit) }

  # Brief §14.1 (Task 4 table). Columns: admin, editor-in-unit,
  # editor-other-unit, viewer.
  MATRIX = [
    [ :index?,   :editor_assignment_record, true, false, false, false ],
    [ :new?,     :editor_assignment_record, true, false, false, false ],
    [ :create?,  :editor_assignment_record, true, false, false, false ],
    [ :destroy?, :editor_assignment_record, true, false, false, false ]
  ].freeze

  USERS = %i[admin_user editor_user other_editor_user viewer_user].freeze

  MATRIX.each do |action, record_name, *expected|
    USERS.each_with_index do |user_name, i|
      it "#{action} on #{record_name} is #{expected[i]} for #{user_name}" do
        policy = described_class.new(send(user_name), send(record_name))
        expect(policy.public_send(action)).to be expected[i]
      end
    end
  end
end

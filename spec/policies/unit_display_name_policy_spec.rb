require "rails_helper"

# MiClassrooms Phase 5 Task 11 (Brief §11.4/§14.1): UnitDisplayNamePolicy —
# reference-data configuration is an admin-only console end to end, no
# editor carve-out (mirrors spec/policies/announcement_policy_spec.rb).
RSpec.describe UnitDisplayNamePolicy do
  include_context "role matrix"

  let(:unit_display_name) { create(:unit_display_name, workspace: workspace) }

  unit_display_name_matrix = [
    [ :index?,   :unit_display_name, true, false, false, false ],
    [ :new?,     :unit_display_name, true, false, false, false ],
    [ :create?,  :unit_display_name, true, false, false, false ],
    [ :edit?,    :unit_display_name, true, false, false, false ],
    [ :update?,  :unit_display_name, true, false, false, false ],
    [ :destroy?, :unit_display_name, true, false, false, false ]
  ]

  unit_display_name_users = %i[admin_user editor_user other_editor_user viewer_user]

  unit_display_name_matrix.each do |action, record_name, *expected|
    unit_display_name_users.each_with_index do |user_name, i|
      it "#{action} on #{record_name} is #{expected[i]} for #{user_name}" do
        policy = described_class.new(send(user_name), send(record_name))
        expect(policy.public_send(action)).to be expected[i]
      end
    end
  end
end

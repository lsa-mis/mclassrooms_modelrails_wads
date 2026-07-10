require "rails_helper"

# MiClassrooms Phase 5 Task 11 (Brief §11.4/§14.1): UnitDisplayNamePolicy —
# reference-data configuration is an admin-only console end to end, no
# editor carve-out (mirrors spec/policies/announcement_policy_spec.rb).
RSpec.describe UnitDisplayNamePolicy do
  include_context "role matrix"

  let(:unit_display_name) { create(:unit_display_name, workspace: workspace) }

  UNIT_DISPLAY_NAME_MATRIX = [
    [ :index?,   :unit_display_name, true, false, false, false ],
    [ :new?,     :unit_display_name, true, false, false, false ],
    [ :create?,  :unit_display_name, true, false, false, false ],
    [ :edit?,    :unit_display_name, true, false, false, false ],
    [ :update?,  :unit_display_name, true, false, false, false ],
    [ :destroy?, :unit_display_name, true, false, false, false ]
  ].freeze

  UNIT_DISPLAY_NAME_USERS = %i[admin_user editor_user other_editor_user viewer_user].freeze

  UNIT_DISPLAY_NAME_MATRIX.each do |action, record_name, *expected|
    UNIT_DISPLAY_NAME_USERS.each_with_index do |user_name, i|
      it "#{action} on #{record_name} is #{expected[i]} for #{user_name}" do
        policy = described_class.new(send(user_name), send(record_name))
        expect(policy.public_send(action)).to be expected[i]
      end
    end
  end
end

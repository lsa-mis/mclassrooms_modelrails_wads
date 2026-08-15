require "rails_helper"

# MiClassrooms Phase 5 Task 11 (Brief §11.4/§14.1): CharacteristicDisplayRulePolicy
# — reference-data configuration is an admin-only console end to end, no
# editor carve-out (mirrors spec/policies/announcement_policy_spec.rb).
RSpec.describe CharacteristicDisplayRulePolicy do
  include_context "role matrix"

  let(:characteristic_display_rule) { create(:characteristic_display_rule, workspace: workspace) }

  characteristic_display_rule_matrix = [
    [ :index?,   :characteristic_display_rule, true, false, false, false ],
    [ :new?,     :characteristic_display_rule, true, false, false, false ],
    [ :create?,  :characteristic_display_rule, true, false, false, false ],
    [ :edit?,    :characteristic_display_rule, true, false, false, false ],
    [ :update?,  :characteristic_display_rule, true, false, false, false ],
    [ :destroy?, :characteristic_display_rule, true, false, false, false ]
  ]

  characteristic_display_rule_users = %i[admin_user editor_user other_editor_user viewer_user]

  characteristic_display_rule_matrix.each do |action, record_name, *expected|
    characteristic_display_rule_users.each_with_index do |user_name, i|
      it "#{action} on #{record_name} is #{expected[i]} for #{user_name}" do
        policy = described_class.new(send(user_name), send(record_name))
        expect(policy.public_send(action)).to be expected[i]
      end
    end
  end
end

require "rails_helper"

# MiClassrooms Phase 5 Task 11 (Brief §11.4/§14.1): SyncScopeRulePolicy —
# reference-data configuration is an admin-only console end to end, no
# editor carve-out (mirrors spec/policies/announcement_policy_spec.rb).
RSpec.describe SyncScopeRulePolicy do
  include_context "role matrix"

  let(:sync_scope_rule) { create(:sync_scope_rule, workspace: workspace) }

  SYNC_SCOPE_RULE_MATRIX = [
    [ :index?,   :sync_scope_rule, true, false, false, false ],
    [ :new?,     :sync_scope_rule, true, false, false, false ],
    [ :create?,  :sync_scope_rule, true, false, false, false ],
    [ :edit?,    :sync_scope_rule, true, false, false, false ],
    [ :update?,  :sync_scope_rule, true, false, false, false ],
    [ :destroy?, :sync_scope_rule, true, false, false, false ]
  ].freeze

  SYNC_SCOPE_RULE_USERS = %i[admin_user editor_user other_editor_user viewer_user].freeze

  SYNC_SCOPE_RULE_MATRIX.each do |action, record_name, *expected|
    SYNC_SCOPE_RULE_USERS.each_with_index do |user_name, i|
      it "#{action} on #{record_name} is #{expected[i]} for #{user_name}" do
        policy = described_class.new(send(user_name), send(record_name))
        expect(policy.public_send(action)).to be expected[i]
      end
    end
  end
end

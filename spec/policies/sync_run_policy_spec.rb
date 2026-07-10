require "rails_helper"

# MiClassrooms Phase 5 Task 4 (Brief §14.1, interpretation 7): SyncRunPolicy
# follows AnalyticsPolicy's same read-only pattern — editors can see sync-run
# history/status (pipeline health visibility), only admins can resume a
# failed run or trigger a manual refresh. Neither predicate reads `record`,
# so a real SyncRun instance is used here purely for realism (SyncRun,
# unlike Analytics, is an actual persisted model).
RSpec.describe SyncRunPolicy do
  include_context "role matrix"

  let(:sync_run) { create(:sync_run) }

  # Brief §14.1 (Task 4 table). Columns: admin, editor-in-unit,
  # editor-other-unit, viewer.
  MATRIX = [
    [ :index?,   :sync_run, true, true,  true,  false ],
    [ :show?,    :sync_run, true, true,  true,  false ],
    [ :resume?,  :sync_run, true, false, false, false ],
    [ :refresh?, :sync_run, true, false, false, false ]
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

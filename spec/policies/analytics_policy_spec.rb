require "rails_helper"

# MiClassrooms Phase 5 Task 4 (Brief §14.1, interpretation 7): AnalyticsPolicy
# is headless — there is no persisted Analytics model, so every caller
# authorizes against a bare `:analytics` symbol (`authorize :analytics,
# :show?`), same pattern as Admin::BulkUploadPolicy. Editors get read-only
# access to the dashboard; only admins can trigger a refresh.
RSpec.describe AnalyticsPolicy do
  include_context "role matrix"

  # Brief §14.1 (Task 4 table). Columns: admin, editor-in-unit,
  # editor-other-unit, viewer. `:analytics` (a bare symbol, not a record) is
  # the record every action is authorized against — neither predicate reads
  # `record` at all.
  ANALYTICS_MATRIX = [
    [ :show?,    :analytics, true, true,  true,  false ],
    [ :refresh?, :analytics, true, false, false, false ]
  ].freeze

  ANALYTICS_USERS = %i[admin_user editor_user other_editor_user viewer_user].freeze

  ANALYTICS_MATRIX.each do |action, record_name, *expected|
    ANALYTICS_USERS.each_with_index do |user_name, i|
      it "#{action} is #{expected[i]} for #{user_name}" do
        policy = described_class.new(send(user_name), record_name)
        expect(policy.public_send(action)).to be expected[i]
      end
    end
  end
end

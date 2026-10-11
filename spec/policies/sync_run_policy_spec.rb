require "rails_helper"

# Admins and editors read sync history; retrying or starting a sync is an operator action (Operations::SyncRunPolicy).
RSpec.describe SyncRunPolicy do
  include_context "role matrix"

  let(:sync_run) { create(:sync_run) }

  # Brief §14.1 (Task 4 table). Columns: admin, editor-in-unit,
  # editor-other-unit, viewer.
  sync_run_matrix = [
    [ :index?,   :sync_run, true, true,  true,  false ],
    [ :show?,    :sync_run, true, true,  true,  false ]
  ]

  # Retrying or starting a sync is an operator action now (Operations::SyncRunPolicy), not a workspace admin's.
  it "answers no workspace-tier action verbs" do
    expect(described_class.new(admin_user, sync_run)).not_to respond_to(:resume?, :refresh?)
  end

  sync_run_users = %i[admin_user editor_user other_editor_user viewer_user]

  sync_run_matrix.each do |action, record_name, *expected|
    sync_run_users.each_with_index do |user_name, i|
      it "#{action} on #{record_name} is #{expected[i]} for #{user_name}" do
        policy = described_class.new(send(user_name), send(record_name))
        expect(policy.public_send(action)).to be expected[i]
      end
    end
  end
end

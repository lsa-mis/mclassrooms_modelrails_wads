FactoryBot.define do
  factory :sync_phase do
    sync_run
    # workspace derives from :sync_run, not a bare association — mirrors the
    # rooms.rb/editor_assignments.rb landmine: pass sync_run: explicitly when
    # overriding workspace, or the two land in different tenants.
    workspace { sync_run.workspace }
    sequence(:key) { |n| SyncPhase::KEYS[n % SyncPhase::KEYS.size] }
  end
end

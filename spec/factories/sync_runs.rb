FactoryBot.define do
  factory :sync_run do
    workspace
    dry_run { false }
  end
end

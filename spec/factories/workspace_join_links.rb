FactoryBot.define do
  factory :workspace_join_link do
    workspace
    association :created_by, factory: :user
    # token auto-generated via has_secure_token
  end
end

FactoryBot.define do
  factory :workspace_join_link do
    workspace
    association :created_by, factory: :user
    # token_digest auto-generated on create; the plaintext is exposed once via
    # the built record's #plaintext_token (used to build join URLs in specs).
  end
end

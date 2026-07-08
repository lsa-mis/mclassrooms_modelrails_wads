FactoryBot.define do
  factory :sync_scope_rule do
    workspace
    rule_type { "campus_allow" }
    sequence(:value) { |n| "SCOPE#{n}" }
  end
end

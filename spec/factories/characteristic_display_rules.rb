FactoryBot.define do
  factory :characteristic_display_rule do
    workspace
    sequence(:short_code) { |n| "Chrstc#{n}" }
    icon_key { "wifi" }
    filterable { true }
    team_learning { false }
  end
end

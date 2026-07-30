FactoryBot.define do
  factory :floor do
    building
    workspace { building.workspace }
    sequence(:label, &:to_s)
    plan_alt { "Floor plan" }

    trait :needs_alt do
      plan_alt { nil }
      plan_derived_ok { false }
    end
  end
end

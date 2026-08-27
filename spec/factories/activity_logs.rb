FactoryBot.define do
  factory :activity_log do
    actor factory: :user
    action { "test.action" }
    association :trackable, factory: :workspace
    workspace { nil }
    visibility { "workspace" }
    metadata { {} }

    # The exact shape ActivityLog.record_security_event! writes — the user is
    # both actor and trackable, personal visibility, no workspace. Pinned
    # against the writer's real output in spec/factory_contracts_spec.rb, so
    # fixtures cannot drift from it (#830). (`:personal` alone also exists,
    # auto-defined from the visibility enum, for rows that are personally
    # scoped without being security events.)
    trait :security do
      visibility { "personal" }
      trackable { actor }
    end
  end
end

FactoryBot.define do
  factory :membership do
    user
    workspace
    role { Role.system_default!("member") }

    trait :owner do
      role { Role.system_default!("owner") }
    end

    # Fixture state set directly; deactivate! runs guards an example may not need.
    trait :deactivated do
      discarded_at { Time.current }
    end

    trait :admin do
      role { Role.system_default!("admin") }
    end

    trait :viewer do
      role { Role.system_default!("viewer") }
    end
  end
end

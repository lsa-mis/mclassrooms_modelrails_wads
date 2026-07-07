FactoryBot.define do
  factory :invitation do
    association :invitable, factory: :workspace
    email { Faker::Internet.email }
    role { Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" } }
    invited_by factory: :user
    expires_at { 7.days.from_now }

    trait :magic_link do
      email { nil }
    end

    trait :accepted do
      status { "accepted" }
      accepted_at { Time.current }
      accepted_by factory: :user
    end

    trait :declined do
      status { "declined" }
      declined_at { Time.current }
    end

    trait :revoked do
      status { "revoked" }
      revoked_at { Time.current }
    end

    trait :expired do
      expires_at { 1.day.ago }
    end
  end
end

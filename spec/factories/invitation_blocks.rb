FactoryBot.define do
  factory :invitation_block do
    inviter factory: :user
    sequence(:email) { |n| "blocked-#{n}@example.com" }
  end
end

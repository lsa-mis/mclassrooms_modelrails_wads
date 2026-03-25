FactoryBot.define do
  factory :workspace do
    name { Faker::Company.name }
    plan { "free" }
  end
end

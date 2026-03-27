FactoryBot.define do
  factory :resource do
    project
    title { Faker::Lorem.sentence(word_count: 3) }
    status { "draft" }
    created_by { project&.created_by || association(:user) }
    position { 0 }
    resourceable factory: :document
  end
end

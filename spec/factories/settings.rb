FactoryBot.define do
  factory :setting do
    sequence(:key) { |n| "setting_#{n}" }
    value { "1" }
  end
end

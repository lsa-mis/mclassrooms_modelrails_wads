FactoryBot.define do
  factory :user_preferences do
    user
    theme { "system" }
  end
end

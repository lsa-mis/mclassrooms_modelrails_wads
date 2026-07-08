FactoryBot.define do
  factory :announcement do
    workspace
    slot { "home_page" }
    body { "Welcome" }
  end
end

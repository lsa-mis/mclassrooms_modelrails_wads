FactoryBot.define do
  factory :client_access do
    project { association(:project, clientside_enabled: true) }
    user
    company_name { "BigCo" }
  end
end

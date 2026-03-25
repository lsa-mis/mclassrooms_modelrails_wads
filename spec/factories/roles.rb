FactoryBot.define do
  factory :role do
    sequence(:name) { |n| "Role #{n}" }
    sequence(:slug) { |n| "role-#{n}" }
    workspace { nil }
    permissions { {} }

    trait :owner do
      name { "Owner" }
      slug { "owner" }
      permissions { { manage_workspace: true, manage_members: true, manage_teams: true, manage_settings: true } }
    end

    trait :admin do
      name { "Admin" }
      slug { "admin" }
      permissions { { manage_members: true, manage_teams: true, manage_settings: true } }
    end

    trait :viewer do
      name { "Viewer" }
      slug { "viewer" }
      permissions { {} }
    end
  end
end

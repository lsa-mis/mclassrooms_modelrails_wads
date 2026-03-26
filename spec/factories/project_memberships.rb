FactoryBot.define do
  factory :project_membership do
    project
    association :user
    role { "editor" }

    before(:create) do |pm|
      next unless pm.project && pm.user
      workspace = pm.project.workspace
      unless workspace.memberships.kept.exists?(user: pm.user)
        create(:membership, user: pm.user, workspace: workspace)
      end
    end

    trait :creator do
      role { "creator" }
    end

    trait :viewer do
      role { "viewer" }
    end

    trait :pinned do
      pinned { true }
    end
  end
end

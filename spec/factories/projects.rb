FactoryBot.define do
  factory :project do
    workspace
    name { Faker::App.name }
    created_by factory: :user

    after(:create) do |project|
      unless project.workspace.memberships.exists?(user: project.created_by)
        create(:membership, user: project.created_by, workspace: project.workspace)
      end
    end
  end
end

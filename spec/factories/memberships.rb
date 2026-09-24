FactoryBot.define do
  factory :membership do
    user
    workspace
    role { Role.find_or_create_by!(slug: "member", workspace_id: nil) { |r| r.name = "Member" } }

    trait :owner do
      role { Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner"; r.permissions = { manage_workspace: true, manage_members: true, manage_settings: true } } }
    end

    # Deactivated as fixture STATE. Sets the column directly on purpose: the
    # domain verb is deactivate!, and an example that only needs a removed member
    # should not run the last-owner guard, the workspace lock and the
    # project-membership cascade to get one.
    trait :deactivated do
      discarded_at { Time.current }
    end

    trait :admin do
      role { Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin"; r.permissions = { manage_members: true, manage_settings: true } } }
    end
  end
end

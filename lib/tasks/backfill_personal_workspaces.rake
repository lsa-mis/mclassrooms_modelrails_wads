namespace :users do
  desc "Create personal workspaces for existing users who don't have one"
  task backfill_personal_workspaces: :environment do
    owner_role = Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
      r.name = "Owner"
      r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
    end

    User.find_each do |user|
      next if user.memberships.kept.joins(:role).where(roles: { slug: "owner" }).exists?

      workspace = Workspace.create!(name: "#{user.first_name}'s Workspace")
      workspace.memberships.create!(user: user, role: owner_role)
      puts "Created personal workspace for #{user.email_address}"
    end
  end
end

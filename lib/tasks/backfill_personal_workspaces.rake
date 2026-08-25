namespace :users do
  desc "Create personal workspaces for existing users who don't have one"
  task backfill_personal_workspaces: :environment do
    User.find_each do |user|
      next if user.memberships.kept.joins(:role).where(roles: { slug: "owner" }).exists?

      workspace = Workspace.create_owned({ name: "#{user.first_name}'s Workspace" }, owner: user)
      raise ActiveRecord::RecordInvalid.new(workspace) unless workspace.persisted?

      puts "Created personal workspace for #{user.email_address}"
    end
  end
end

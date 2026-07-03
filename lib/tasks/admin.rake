namespace :users do
  desc "Unlock a locked user account"
  task :unlock, [ :email ] => :environment do |_t, args|
    abort "Usage: rails users:unlock[email@example.com]" unless args[:email]
    user = User.find_by!(email_address: args[:email])
    user.update!(failed_login_attempts: 0, locked_at: nil)
    puts "Unlocked #{user.email_address}"
  rescue ActiveRecord::RecordNotFound
    abort "User not found: #{args[:email]}"
  end

  desc "Verify a user's email address"
  task :verify, [ :email ] => :environment do |_t, args|
    abort "Usage: rails users:verify[email@example.com]" unless args[:email]
    user = User.find_by!(email_address: args[:email])
    auth = user.authentications.email.first
    abort "No email authentication found for #{user.email_address}" unless auth
    if auth.verified?
      puts "#{user.email_address} is already verified"
    else
      auth.verify!
      puts "Verified #{user.email_address}"
    end
  rescue ActiveRecord::RecordNotFound
    abort "User not found: #{args[:email]}"
  end

  desc "Suspend a user — destroy sessions, deactivate all memberships"
  task :suspend, [ :email ] => :environment do |_t, args|
    abort "Usage: rails users:suspend[email@example.com]" unless args[:email]
    user = User.find_by!(email_address: args[:email])
    user.sessions.destroy_all
    user.memberships.kept.find_each(&:discard!)
    puts "Suspended #{user.email_address} — all sessions destroyed, all memberships deactivated"
  rescue ActiveRecord::RecordNotFound
    abort "User not found: #{args[:email]}"
  end
end

namespace :workspaces do
  desc "Suspend (lock) a workspace — owners are blocked until unsuspended"
  task :suspend, [ :slug ] => :environment do |_t, args|
    abort "Usage: rails workspaces:suspend[slug]" unless args[:slug]
    workspace = Workspace.find_by!(slug: args[:slug])
    workspace.suspend!
    puts "Suspended #{workspace.slug} — owner lifecycle actions and all workspace pages are blocked"
  rescue ActiveRecord::RecordNotFound
    abort "Workspace not found: #{args[:slug]}"
  end

  desc "Unsuspend (unlock) a workspace"
  task :unsuspend, [ :slug ] => :environment do |_t, args|
    abort "Usage: rails workspaces:unsuspend[slug]" unless args[:slug]
    workspace = Workspace.find_by!(slug: args[:slug])
    workspace.unsuspend!
    puts "Unsuspended #{workspace.slug}"
  rescue ActiveRecord::RecordNotFound
    abort "Workspace not found: #{args[:slug]}"
  end
end

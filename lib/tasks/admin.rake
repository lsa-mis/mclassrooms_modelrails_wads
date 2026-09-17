namespace :users do
  desc "Unlock a locked user account"
  task :unlock, [ :email ] => :environment do |_t, args|
    abort "Usage: rails users:unlock[email@example.com]" unless args[:email]
    user = User.find_by!(email_address: args[:email])
    case user.unlock!(by: nil)
    when :unlocked
      puts "Unlocked #{user.email_address}"
    when :not_locked
      puts "#{user.email_address} is not locked"
    end
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

  desc "Suspend a user — sessions end, sign-in is blocked, memberships are untouched"
  task :suspend, [ :email ] => :environment do |_t, args|
    abort "Usage: rails users:suspend[email@example.com]" unless args[:email]
    user = User.find_by!(email_address: args[:email])
    case user.suspend!(by: nil)
    when :suspended
      puts "Suspended #{user.email_address} — sessions ended, sign-in blocked until unsuspended"
    when :already_suspended
      puts "#{user.email_address} is already suspended"
    end
  rescue ActiveRecord::RecordNotFound
    abort "User not found: #{args[:email]}"
  end

  desc "Unsuspend a user — restores sign-in"
  task :unsuspend, [ :email ] => :environment do |_t, args|
    abort "Usage: rails users:unsuspend[email@example.com]" unless args[:email]
    user = User.find_by!(email_address: args[:email])
    case user.unsuspend!(by: nil)
    when :unsuspended
      puts "Unsuspended #{user.email_address}"
    when :not_suspended
      puts "#{user.email_address} is not suspended"
    end
  rescue ActiveRecord::RecordNotFound
    abort "User not found: #{args[:email]}"
  end
end

namespace :workspaces do
  desc "Suspend (lock) a workspace — owners are blocked until unsuspended"
  task :suspend, [ :slug ] => :environment do |_t, args|
    abort "Usage: rails workspaces:suspend[slug]" unless args[:slug]
    workspace = Workspace.find_by!(slug: args[:slug])
    case workspace.suspend!
    when :suspended
      puts "Suspended #{workspace.slug} — owner lifecycle actions and all workspace pages are blocked"
    when :already_suspended
      puts "#{workspace.slug} is already suspended"
    end
  rescue ActiveRecord::RecordNotFound
    abort "Workspace not found: #{args[:slug]}"
  end

  desc "Unsuspend (unlock) a workspace"
  task :unsuspend, [ :slug ] => :environment do |_t, args|
    abort "Usage: rails workspaces:unsuspend[slug]" unless args[:slug]
    workspace = Workspace.find_by!(slug: args[:slug])
    case workspace.unsuspend!
    when :unsuspended
      puts "Unsuspended #{workspace.slug}"
    when :not_suspended
      puts "#{workspace.slug} is not suspended"
    end
  rescue ActiveRecord::RecordNotFound
    abort "Workspace not found: #{args[:slug]}"
  end
end

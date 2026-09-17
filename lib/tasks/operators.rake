# Bootstrap and break-glass for instance operators. The first operator cannot
# come from the operations panel (nobody can reach it yet), same as
# tenancy:owner_setup_link. See /docs/developer/operations.
namespace :operators do
  desc "Grant instance-operator access to a user"
  task :grant, [ :email ] => :environment do |_t, args|
    abort "Usage: rails operators:grant[email@example.com]" unless args[:email]
    user = User.find_by!(email_address: args[:email])
    if user.operator?
      puts "#{user.email_address} is already an operator"
    else
      Operatorship.grant!(user: user)
      puts "Granted operator access to #{user.email_address}"
    end
    # The operator vouches for the address (they typed it), as the :shared
    # seed does for its bootstrap owner — without a verified row the account
    # cannot send the invitation its first create-for-owner issues. Create
    # only: a pending round-trip is never converted. Listed in
    # spec/requests/can_invite_gate_spec.rb's writer inventory.
    user.authentications.find_or_create_by!(provider: "email") do |auth|
      auth.email = user.email_address
      auth.verified_at = Time.current
    end
  rescue ActiveRecord::RecordNotFound
    abort "User not found: #{args[:email]}"
  end

  desc "Revoke instance-operator access from a user"
  task :revoke, [ :email ] => :environment do |_t, args|
    abort "Usage: rails operators:revoke[email@example.com]" unless args[:email]
    user = User.find_by!(email_address: args[:email])
    operatorship = user.operatorships.kept.first
    abort "#{user.email_address} is not an operator" unless operatorship
    operatorship.revoke!
    puts "Revoked operator access from #{user.email_address}"
  rescue ActiveRecord::RecordNotFound
    abort "User not found: #{args[:email]}"
  end

  desc "List instance operators"
  task list: :environment do
    rows = Operatorship.kept.includes(:user, :granted_by).order(:created_at)
    if rows.empty?
      puts "No operators"
    else
      rows.each do |o|
        puts "#{o.user.email_address}  granted #{o.created_at.to_date} by #{o.granted_by&.email_address || 'rake/seed'}"
      end
    end
  end
end

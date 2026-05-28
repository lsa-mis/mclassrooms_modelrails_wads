default_roles = {
  owner:  { name: "Owner",  permissions: { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true } },
  admin:  { name: "Admin",  permissions: { manage_members: true, manage_projects: true, manage_settings: true } },
  member: { name: "Member", permissions: { manage_projects: true } },
  viewer: { name: "Viewer", permissions: {} }
}

default_roles.each do |slug, attrs|
  Role.find_or_create_by!(slug: slug.to_s, workspace_id: nil) do |r|
    r.name = attrs[:name]
    r.permissions = attrs[:permissions]
  end
end

# --- Single-tenant preset bootstrap ----------------------------------------
#
# When TENANCY_ONBOARDING=shared, seed the shared workspace + the initial
# Owner so the deployment is usable on first boot. Idempotent — safe to re-run.
# See app/docs/presets.md for the contract.
if TenancyConfig.shared?
  slug = ENV.fetch("TENANCY_SHARED_WORKSPACE_SLUG") {
    raise "TENANCY_SHARED_WORKSPACE_SLUG is required when TENANCY_ONBOARDING=shared"
  }
  name = ENV.fetch("TENANCY_SHARED_WORKSPACE_NAME", slug.titleize)
  owner_email = ENV.fetch("TENANCY_OWNER_EMAIL") {
    raise "TENANCY_OWNER_EMAIL is required when TENANCY_ONBOARDING=shared"
  }

  workspace = Workspace.find_or_create_by!(slug: slug) do |w|
    w.name = name
    w.personal = false
  end

  # Creating the User triggers User#onboard_workspace, which (under :shared)
  # adds a Member-role Membership to `workspace`. The seed then upgrades that
  # membership to Owner below — idempotent on re-runs.
  owner = User.find_or_create_by!(email_address: owner_email) do |u|
    u.first_name = ENV.fetch("TENANCY_OWNER_FIRST_NAME", "Workspace")
    u.last_name  = ENV.fetch("TENANCY_OWNER_LAST_NAME",  "Owner")
    placeholder  = SecureRandom.urlsafe_base64(32)
    u.password = placeholder
    u.password_confirmation = placeholder
  end

  # Operator vouches for the email (they supplied it); the password-set link
  # closes the loop by requiring inbox access.
  owner.authentications.find_or_create_by!(provider: "email", uid: owner.email_address) do |auth|
    auth.email = owner.email_address
    auth.verified_at = Time.current
  end

  owner_role = Role.find_by!(slug: "owner", workspace_id: nil)
  membership = workspace.memberships.find_or_create_by!(user: owner) { |m| m.role = owner_role }
  membership.update!(role: owner_role) unless membership.role_id == owner_role.id

  # Deliver a password-set link so the owner can claim the account. In
  # production we log the URL for out-of-band delivery (email infra may not
  # be ready on first boot); in dev/test the mailer runs normally.
  if Rails.env.production?
    host = ENV.fetch("APP_HOST", "localhost")
    url = Rails.application.routes.url_helpers.edit_password_url(token: owner.password_reset_token, host: host)
    Rails.logger.info "[tenancy] Owner account seeded for #{owner_email}. Password-set URL: #{url}"
  else
    AuthenticationMailer.password_reset_email(owner).deliver_now
  end
end

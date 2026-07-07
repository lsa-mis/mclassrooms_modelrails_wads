# Canonical definitions live in Role::SYSTEM_DEFAULTS — one source of truth
# for seeds and every request-time Role.system_default! lookup.
Role::SYSTEM_DEFAULTS.each_key { |slug| Role.system_default!(slug) }

# --- Single-tenant preset bootstrap ----------------------------------------
#
# When TENANCY_ONBOARDING=shared, seed the shared workspace + the initial
# Owner so the deployment is usable on first boot. Idempotent — safe to re-run.
# See app/docs/developer/presets.md for the contract.
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

  # Help the owner claim the account. In production we do NOT log a password
  # token: the link would be minted at deploy time (its short expiry clock
  # already ticking) and would linger as a live credential in log retention.
  # Instead, log the workspace URL and point at `tenancy:owner_setup_link`,
  # which mints a fresh short-lived link on demand, when the operator is ready.
  # In dev/test the mailer runs normally.
  if Rails.env.production?
    host = ENV.fetch("APP_HOST", "localhost")
    workspace_url = Rails.application.routes.url_helpers.workspace_url(workspace, host: host)
    Rails.logger.info "[tenancy] Owner account seeded for #{owner_email}. " \
      "Workspace: #{workspace_url}. " \
      "Run `bin/rails tenancy:owner_setup_link` for a short-lived sign-in link " \
      "(minted on demand — not logged here)."
  else
    # Bug fix (MiClassrooms Task 4): this called AuthenticationMailer.password_reset_email,
    # which does not exist in this codebase's passwordless-first auth mailers —
    # it raised NoMethodError on every db:seed run under the :shared preset
    # outside production (spec/db/seeds_spec.rb only covers the production
    # branch above, so this line was never exercised). Use the same
    # magic-link mechanism the app's own password-reset flow
    # (PasswordResetsController#create) and `tenancy:owner_setup_link` use.
    token = MagicLinkToken.create_for_email(owner.email_address, intent: "set_password")
    MagicLinkMailer.sign_in_link(owner.email_address, token).deliver_now
  end
end

# === Template seeds end here =================================================
# Fork seam: add your app's domain seeds BELOW this line. Upstream owns
# everything above it; keeping your additions below the marker keeps
# `git merge upstream/main` conflicts away. See /docs/developer/forking.

# Canonical definitions live in Role::SYSTEM_DEFAULTS — one source of truth
# for seeds and every request-time Role.system_default! lookup.
Role::SYSTEM_DEFAULTS.each_key { |slug| Role.system_default!(slug) }

# Under the shared preset, seed the shared workspace and its first Owner so the app works on first boot.
# Idempotent. The slug is the one the app resolved, which a fork's .fork.yml supplies by default.
if TenancyConfig.shared?
  slug = TenancyConfig.shared_workspace_slug
  name = ENV.fetch("TENANCY_SHARED_WORKSPACE_NAME") { I18n.t("application.name", default: slug.titleize) }
  # bin/setup's db:prepare never sees .env (only foreman loads it), so a fresh fork's owner is a placeholder.
  owner_email = ENV.fetch("TENANCY_OWNER_EMAIL") {
    raise "TENANCY_OWNER_EMAIL is required when WORKSPACE_ON_SIGNUP=shared" if Rails.env.production?

    "owner@#{slug.dasherize}.test"
  }

  workspace = Workspace.find_or_create_by!(slug: slug) do |w|
    w.name = name
    w.personal = false
  end

  owner_role = Role.find_by!(slug: "owner", workspace_id: nil)
  # Onboarding seats a new owner as Owner, so no promotion follows to mail them a role change.
  owner = User.find_or_create_by!(email_address: owner_email) do |u|
    u.shared_workspace_role = owner_role
    u.first_name = ENV.fetch("TENANCY_OWNER_FIRST_NAME", "Workspace")
    u.last_name  = ENV.fetch("TENANCY_OWNER_LAST_NAME",  "Owner")
    placeholder  = SecureRandom.urlsafe_base64(32)
    u.password = placeholder
    u.password_confirmation = placeholder
  end

  # Operator vouches for the email (they supplied it); the password-set link
  # closes the loop by requiring inbox access.
  owner.authentications.find_or_create_by!(provider: "email") do |auth|
    auth.email = owner.email_address
    auth.verified_at = Time.current
  end

  membership = workspace.memberships.find_or_create_by!(user: owner) { |m| m.role = owner_role }
  membership.update!(role: owner_role) unless membership.role_id == owner_role.id

  # The bootstrap owner also operates the instance — see operations.md "Day
  # one". Guarded on any operatorship row ever existing, kept or discarded:
  # re-seeding must not resurrect a grant a break-glass revoke deliberately
  # took away. A racing second seed loses to the partial unique index; treat
  # that as already granted.
  begin
    Operatorship.grant!(user: owner) unless owner.operatorships.exists?
  rescue ActiveRecord::RecordNotUnique
    nil
  end

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
    token = MagicLinkToken.create_for_email(owner.email_address, intent: "set_password")
    MagicLinkMailer.sign_in_link(owner.email_address, token).deliver_now
  end
end

# === Template seeds end here =================================================
# Fork seam: add your app's domain seeds BELOW this line. Upstream owns
# everything above it; keeping your additions below the marker keeps
# `git merge upstream/main` conflicts away. See /docs/developer/forking.

# --- MiClassrooms domain seeds (fork-owned) ---------------------------------
if TenancyConfig.shared?
  shared_workspace = Workspace.find_by!(slug: TenancyConfig.shared_workspace_slug)
  ReferenceData.seed!(workspace: shared_workspace)
end

# --- MiClassrooms DEV-ONLY sample data (fork-owned) --------------------------
# Populates Find a Room / room pages / admin consoles with realistic
# browsable data — buildings, floors, units, rooms, characteristics, editor
# assignments, notes, and announcements. Guarded so it NEVER runs outside
# development, and only ever writes to the shared workspace (never any
# other tenant). See db/seeds/development_sample.rb; also runnable standalone
# via `rails dev:sample_data` (lib/tasks/dev.rake). Idempotent either way.
# Disabled: real U-M data is now loaded via `rails "um:import"` (the
# production-proven gateway recipe — see lib/tasks/um_import.rake), so db:seed
# no longer auto-populates fake sample data into the shared workspace. The
# fake dataset is still available on demand via `rails dev:sample_data` for
# offline work without gateway credentials.
# if Rails.env.development? && TenancyConfig.shared?
#   require_relative "seeds/development_sample"
#   DevelopmentSampleData.seed!
# end

# Validates tenancy preset configuration at boot so mistyped ENV values
# fail fast instead of surprising at request time. See app/docs/developer/presets.md
# for the preset configuration contract.

valid_onboarding = [ :personal, :shared, :none ]
unless valid_onboarding.include?(Rails.configuration.x.tenancy.onboarding)
  raise "Invalid WORKSPACE_ON_SIGNUP: #{Rails.configuration.x.tenancy.onboarding.inspect}. " \
        "Must be one of: #{valid_onboarding.join(', ')}"
end

valid_workspace_creation = %i[enabled disabled]
unless valid_workspace_creation.include?(Rails.configuration.x.tenancy.workspace_creation)
  raise "Invalid TENANCY_WORKSPACE_CREATION: #{Rails.configuration.x.tenancy.workspace_creation.inspect}. " \
        "Must be one of: #{valid_workspace_creation.join(', ')}"
end

if Rails.configuration.x.tenancy.onboarding == :shared &&
   Rails.configuration.x.tenancy.shared_workspace_slug.blank?
  raise "TENANCY_SHARED_WORKSPACE_SLUG is required when WORKSPACE_ON_SIGNUP=shared"
end

# Note: TENANCY_SHARED_JOIN_ROLE (config.x.tenancy.shared_join_role, see
# config/application.rb) is deliberately NOT validated here. Role::SYSTEM_DEFAULTS
# lives in app/models/role.rb, which Zeitwerk hasn't wired up as an autoloadable
# constant yet at this point in boot (the main autoloader is set up by a
# Finisher initializer that runs after config/initializers load) — referencing
# it here raises NameError. Role.system_default!(slug) already raises a clear
# KeyError on an unrecognized slug the first time a user joins the shared
# workspace (see User#join_shared_workspace), which is an acceptable deferred
# fail-fast (mirrors how a missing shared workspace is only detected there too).

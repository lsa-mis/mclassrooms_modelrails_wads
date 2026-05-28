# Validates tenancy preset configuration at boot so mistyped ENV values
# fail fast instead of surprising at request time. See app/docs/presets.md
# for the preset configuration contract.

valid_onboarding = %i[personal shared]
unless valid_onboarding.include?(Rails.configuration.x.tenancy.onboarding)
  raise "Invalid TENANCY_ONBOARDING: #{Rails.configuration.x.tenancy.onboarding.inspect}. " \
        "Must be one of: #{valid_onboarding.join(', ')}"
end

valid_workspace_creation = %i[enabled disabled]
unless valid_workspace_creation.include?(Rails.configuration.x.tenancy.workspace_creation)
  raise "Invalid TENANCY_WORKSPACE_CREATION: #{Rails.configuration.x.tenancy.workspace_creation.inspect}. " \
        "Must be one of: #{valid_workspace_creation.join(', ')}"
end

if Rails.configuration.x.tenancy.onboarding == :shared &&
   Rails.configuration.x.tenancy.shared_workspace_slug.blank?
  raise "TENANCY_SHARED_WORKSPACE_SLUG is required when TENANCY_ONBOARDING=shared"
end

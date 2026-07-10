namespace :dev do
  desc "Seed realistic DEV-ONLY sample data (buildings/rooms/units/etc.) into the shared workspace"
  task sample_data: :environment do
    unless Rails.env.development?
      abort "dev:sample_data only runs in development (current env: #{Rails.env})"
    end
    unless TenancyConfig.shared?
      abort "dev:sample_data requires TENANCY_ONBOARDING=shared (current: #{TenancyConfig.onboarding.inspect})"
    end

    require_relative "../../db/seeds/development_sample"
    DevelopmentSampleData.seed!
    puts "[dev:sample_data] done."
  end
end

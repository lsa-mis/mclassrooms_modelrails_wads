require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ModelrailsBase
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    config.yjit = true

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    config.x.signup.mode = ENV.fetch("SIGNUP_MODE", "invite_only").to_sym

    # Instance ceiling on per-workspace Workspace#join_policy. Defaults to
    # [:invite] (preserves Solo-default). Operators opt in to :open_link by
    # setting SIGNUP_PERMITTED_JOIN_STRATEGIES=invite,open_link.
    # See app/docs/developer/presets.md and docs/reshape-2-per-workspace-join-policy-spec.md.
    config.x.signup.permitted_join_strategies =
      ENV.fetch("SIGNUP_PERMITTED_JOIN_STRATEGIES", "invite").split(",").map { |s| s.strip.to_sym }

    # Tenancy preset configuration. See app/docs/developer/presets.md.
    config.x.tenancy.onboarding          = ENV.fetch("WORKSPACE_ON_SIGNUP", "personal").to_sym
    config.x.tenancy.workspace_creation  = ENV.fetch("TENANCY_WORKSPACE_CREATION", "enabled").to_sym
    config.x.tenancy.shared_workspace_slug = ENV["TENANCY_SHARED_WORKSPACE_SLUG"]

    # Fork deviation (MiClassrooms Task 4): role slug granted by
    # User#join_shared_workspace to a user self-joining the shared workspace
    # under the :shared preset. The template hardcodes "member"; this knob
    # lets a fork override it (MiClassrooms sets TENANCY_SHARED_JOIN_ROLE=viewer
    # — see .env.example and app/lib/tenancy_config.rb#shared_join_role).
    # Default "member" preserves upstream behavior when unset.
    config.x.tenancy.shared_join_role = ENV.fetch("TENANCY_SHARED_JOIN_ROLE", "member")
  end
end

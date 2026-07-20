# LSA TeamDynamix feedback backend + adopted modal (Phase 8). We render the
# gem's own self-contained feedback modal site-wide (see the app layout), themed
# to our WCAG 2.2 AAA gate by app/assets/stylesheets/lsa_tdx_feedback_overrides.css,
# and route its submission through LsaTdxFeedback::FeedbackController (our
# app/controllers override) -> Feedback::Submit, which files a TeamDynamix
# ticket or falls back to emailing the directory's admins.
#
# Every TDX value is ENV-sourced with no default. When TDX isn't fully
# configured (any value missing), LsaTdxFeedback.configuration.valid? is false
# and Feedback::Submit emails the admins instead — so feedback works before TDX
# creds land, and never silently disappears.
#
# The gem's OAuth token cache runs through Rails.cache (Solid Cache here — no
# Redis needed, despite the gem's vestigial redis dependency).
LsaTdxFeedback.configure do |config|
  config.oauth_url                    = ENV["TDX_OAUTH_URL"]
  config.api_base_url                 = ENV["TDX_API_BASE_URL"]
  config.client_id                    = ENV["TDX_CLIENT_ID"]
  config.client_secret                = ENV["TDX_CLIENT_SECRET"]
  config.app_id                       = ENV["TDX_APP_ID"]&.to_i
  config.account_id                   = ENV["TDX_ACCOUNT_ID"]&.to_i
  config.service_offering_id          = ENV["TDX_SERVICE_OFFERING_ID"]&.to_i
  config.default_type_id              = ENV["TDX_TYPE_ID"]&.to_i
  config.default_form_id              = ENV["TDX_FORM_ID"]&.to_i
  config.default_classification       = ENV["TDX_CLASSIFICATION"]
  config.default_status_id            = ENV["TDX_STATUS_ID"]&.to_i
  config.default_priority_id          = ENV["TDX_PRIORITY_ID"]&.to_i
  config.default_source_id            = ENV["TDX_SOURCE_ID"]&.to_i
  config.default_responsible_group_id = ENV["TDX_RESPONSIBLE_GROUP_ID"]&.to_i
  config.default_service_id           = ENV["TDX_SERVICE_ID"]&.to_i
end

# Whether to render the gem's built-in floating trigger button site-wide. We
# ALSO open the modal from our own controls (the footer "Send feedback" button
# + the /contact CTA), so this toggles only the *extra* floating button —
# default on; set FEEDBACK_FLOATING_TRIGGER=false to rely on our controls alone
# (e.g. to avoid the fixed button overlapping other bottom-fixed chrome like the
# cookie banner). Read via FeedbackHelper#feedback_floating_trigger?. Fork mirror
# of the gem's upstream trigger opt-out.
Rails.application.config.x.feedback_floating_trigger =
  ENV.fetch("FEEDBACK_FLOATING_TRIGGER", "true") != "false"

# The gem includes ApplicationControllerExtensions into EVERY controller
# (initializer 'lsa_tdx_feedback.action_controller' -> on_load :action_controller),
# adding a global `before_action :set_lsa_tdx_feedback_data` that sets the ivars
# the modal reads (prefilled email, page URL, user-agent, app name).
#
# The gem's own implementation logs `current_user&.email` UNCONDITIONALLY, which
# raises NameError on any controller that doesn't define current_user —
# ViewComponent's preview controller, Rails' health/ActiveStorage controllers,
# etc. (This is the crash we're fixing upstream: guard that one call.) We
# redefine the method fork-side with a crash-proof body that reads only always-
# safe accessors (`request.*`, `Current.user`, `I18n.t`) and sources the app
# name from our brand key so the modal title honors the brand invariant. The
# redefinition lands in the module so every already-including controller picks
# it up through the ancestor chain.
Rails.application.config.to_prepare do
  LsaTdxFeedback::ApplicationControllerExtensions.module_eval do
    def set_lsa_tdx_feedback_data
      @lsa_tdx_feedback_current_url = request.original_url
      @lsa_tdx_feedback_user_agent  = request.user_agent
      @lsa_tdx_feedback_app_name    = I18n.t("application.name", default: nil)
      @lsa_tdx_feedback_user_email  = Current.user&.email_address
    end
  end
end

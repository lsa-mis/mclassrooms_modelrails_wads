# LSA TeamDynamix feedback backend (Phase 8 Task 1). We call
# LsaTdxFeedback::TicketClient directly from Feedback::Submit; the feedback
# form/UI is our own modelrails_ui/AAA surface (the gem's self-contained modal
# predates our WCAG 2.2 AAA + strict-CSP gates), so the gem's engine is NOT
# mounted and its view helpers are unused.
#
# Every value is ENV-sourced with no default. When TDX isn't fully configured
# (any value missing), LsaTdxFeedback.configuration.valid? is false and
# Feedback::Submit falls back to emailing the directory's admins — so feedback
# works before TDX creds land, and never silently disappears.
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

# The gem's engine includes ApplicationControllerExtensions into EVERY controller
# (initializer 'lsa_tdx_feedback.action_controller' -> on_load :action_controller),
# adding a global `before_action :set_lsa_tdx_feedback_data`. That method calls
# `current_user` UNCONDITIONALLY (in a log line), which raises NameError on any
# controller that doesn't define it — ViewComponent's preview controller (333
# preview specs), Rails' health/ActiveStorage controllers, etc. Those ivars only
# feed the gem's self-contained modal, which we don't render (we call
# LsaTdxFeedback::TicketClient directly from our own form). The gem exposes no
# opt-out, so neutralize the hook to a no-op — redefined in the module so every
# already-including controller picks it up through the ancestor chain.
Rails.application.config.to_prepare do
  LsaTdxFeedback::ApplicationControllerExtensions.module_eval do
    def set_lsa_tdx_feedback_data; end
  end
end

# load_defaults 8.2 sends the rest; Permissions-Policy is the one header Rails does not.
Rails.application.config.action_dispatch.default_headers.merge!(
  "Permissions-Policy" => "camera=(), microphone=(), geolocation=()"
)

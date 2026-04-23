Rails.application.config.to_prepare do
  next unless Rails.env.development?
  next unless defined?(LetterOpenerWeb::ApplicationController)

  LetterOpenerWeb::ApplicationController.content_security_policy false
end

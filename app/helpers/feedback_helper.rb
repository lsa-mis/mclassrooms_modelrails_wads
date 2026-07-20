module FeedbackHelper
  # Whether to render the lsa_tdx_feedback gem's built-in floating trigger
  # button (see the modal partial). The /contact CTA opens the modal regardless
  # of this setting — it only governs the always-on floating button, so turning
  # this off leaves /contact as the entry point. Configured from FEEDBACK_FLOATING_TRIGGER
  # (config/initializers/lsa_tdx_feedback.rb); default on.
  def feedback_floating_trigger?
    Rails.configuration.x.feedback_floating_trigger
  end
end

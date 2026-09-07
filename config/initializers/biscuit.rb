# frozen_string_literal: true

# Every cookie this app sets, classified once (#714). Rule: a first-party
# cookie that stores a choice the user just made through a control, carries
# no identifier, and is read by no third party is `necessary` and needs no
# consent. Anything that profiles, measures, or is read by a third party goes
# in its Biscuit category and its write is gated on that category's consent
# (Biscuit's consent check — name the method the gem provides when the first
# such cookie arrives). The docs' "Cookie classification" section lists the
# same set; spec/initializers/cookie_classification_spec.rb holds both together.
#
# Two session cookies exist and both count: `session_id` is the app's own
# signed cookie (Authenticatable#start_new_session_for) backing the DB
# Session record; Rails' own cookie-store session — carrying flash, the CSRF
# token, and short-lived flow state (pending_join_token,
# return_to_after_authenticating) — rides under the app's configured key
# (config.session_options[:key], `_modelrails_base_session` by default; a
# fork's own app name changes it).
# `session_options[:key]` isn't resolved yet at initializer-run time (the
# session middleware sets it later in boot), so this waits for after_initialize.
Rails.application.config.after_initialize do
  Rails.application.config.cookie_classification = {
    session_id: { category: :necessary, reason: "authentication session" },
    Rails.application.config.session_options[:key].to_sym => {
      category: :necessary,
      reason: "Rails' encrypted session cookie: CSRF token, flash messages, and short-lived flow " \
              "state (pending join/invitation tokens, post-auth redirect target)"
    },
    biscuit_consent: { category: :necessary, reason: "the consent record itself" },
    theme: { category: :necessary, reason: "display choice made through a control; no identifier; first-party" },
    sidebar_collapsed: { category: :necessary, reason: "layout choice made through a control; no identifier; first-party" }
  }.freeze
end

Biscuit.configure do |config|
  config.categories = {
    necessary:   { required: true },
    analytics:   { required: false },
    preferences: { required: false },
    marketing:   { required: false }
  }

  config.cookie_name = "biscuit_consent"
  config.cookie_expires_days = 365
  config.cookie_same_site = "Lax"
  config.position = :bottom
  config.privacy_policy_url = "/privacy"
end

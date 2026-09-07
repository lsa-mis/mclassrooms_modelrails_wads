# frozen_string_literal: true

# The one thing a brand-new account's notifications page has on day one: a
# welcome that names what this page carries and points at the preferences
# that control it.
#
# Deliberately NOT a User callback. `User` has `after_create
# :onboard_workspace`, so every `create(:user)` in the suite runs the signup
# path — a callback-fired welcome would add a notification row behind every
# factory user and silently shift every notification count in the suite. The
# dispatch sites are the real registration entry points instead
# (MagicLinkCallbacksController#create and OauthLink's two signup branches),
# which no factory reaches.
#
# In-app only, no email leg: someone who just registered is already in the
# app, and signup's own mail (magic link, OAuth verification) is the last
# thing a second welcome email should be competing with.
class WelcomeNotifier < ApplicationNotifier
  category :account_access
  severity :info

  recipients do
    permitted_in_app([ record ].compact)
  end

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.welcome.message",
          locale: recipient_locale,
          user_name: event.record.first_name
        )
      end
    end

    # Preferences, not the workspace: the point is to teach that this page
    # exists and that its contents are tunable.
    def url
      Rails.application.routes.url_helpers.edit_settings_notification_preferences_path
    end
  end
end

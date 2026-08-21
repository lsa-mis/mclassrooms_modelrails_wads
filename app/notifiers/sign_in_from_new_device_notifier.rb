# frozen_string_literal: true

# Fires the first time a user signs in from a (user_agent, os) digest we
# haven't recorded for them. Mirrors PasswordChangedNotifier's shape:
# `category :security` so it auto-registers as a security type and bypasses
# DND, with both in-app and email channels gated by per-recipient
# preferences. Email uses the `before_enqueue throw(:abort)` idiom so an
# opt-out skips the job entirely rather than enqueueing-then-discarding.
class SignInFromNewDeviceNotifier < ApplicationNotifier
  category :security
  severity :danger
  # `record` here is the user, so the base (class, record.id, minute) key
  # would collapse two distinct devices signing in within the same minute —
  # a phisher signing in seconds after the legitimate user would silently
  # lose their alert to the dedup index, and a user switching laptop→phone
  # would only see the first alert. Folding the same browser digest used by
  # `User.browser_digest` into the seed makes dedup (user, device, minute) —
  # collapse only on a true same-device retry, the legitimate dedup case.
  # 12 hex chars (~48 bits) is plenty: the goal is differentiation between
  # devices for one user inside a one-minute window, not cryptographic
  # uniqueness; truncation keeps the column readable in logs.
  dedup_seed { User.browser_digest(params[:user_agent], params[:os])[0, 12] }

  required_param :user_agent, :os

  deliver_by :email do |config|
    config.mailer = "NotificationMailer"
    config.method = :sign_in_from_new_device
    config.before_enqueue = -> { throw(:abort) unless deliver_email_now? }
    config.enqueue = true
  end

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.sign_in_from_new_device.message",
          locale: recipient_locale,
          os: event.params[:os]
        )
      end
    end

    def url
      Rails.application.routes.url_helpers.settings_connected_accounts_path
    end
  end
end

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

  required_param :user_agent, :os

  deliver_by :email do |config|
    config.mailer = "NotificationMailer"
    config.method = :sign_in_from_new_device
    # `== true` to abort on the :digest tri-state sentinel; see
    # WorkspaceMemberAddedNotifier for the full rationale. Security-category
    # users effectively never see :digest because allow? returns true at Step 1
    # before frequency check, but the guard matches sibling notifiers so the
    # pattern is uniform.
    config.before_enqueue = -> { throw(:abort) unless recipient_pref(:email) == true }
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

  private

  # Override the base seed so two distinct devices signing in for the same
  # user within the same minute don't collapse onto a single event.
  #
  # The base ApplicationNotifier seeds (class, record.id, minute). Here
  # `record` is the user — meaning a phisher signing in seconds after the
  # legitimate user would silently lose their alert to the dedup index, or a
  # user switching from laptop to phone would only see the first alert. By
  # folding the same browser digest used by `User.browser_digest` into the
  # key, dedup is now (user, device, minute) — collapse only on a true
  # same-device retry, which IS the legitimate dedup case.
  #
  # 12 hex chars (~48 bits) is plenty: the goal is differentiation between
  # devices for one user inside a one-minute window, not cryptographic
  # uniqueness. Truncation keeps the column readable in logs.
  def populate_idempotency_key
    return if idempotency_key.present?

    digest_short = User.browser_digest(params[:user_agent], params[:os])[0, 12]
    self.idempotency_key = "#{self.class.name}_#{record.id}_#{digest_short}_#{Time.current.to_i / 60}"
  end
end

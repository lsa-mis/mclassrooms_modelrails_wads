# frozen_string_literal: true

module Passkeys
  # Authenticated endpoints for adding a passkey to the current user's account.
  # Requires an active session — unauthenticated requests are redirected to sign-in
  # by the default Authenticatable before_action.
  class RegistrationsController < ApplicationController
    # force: — enrollment stays gated even when reauth_enabled is off; it's the
    # one gated action that mints a durable credential and revokes nothing.
    before_action -> { require_reauthentication!(force: true) }, only: [ :options, :verify ]
    def options
      render json: RegisterCeremony.options(user: Current.user)
    end

    def verify
      begin
        RegisterCeremony.verify(
          user: Current.user,
          credential_params: params.to_unsafe_h,
          nickname: params[:nickname]
        )
      rescue ArgumentError
        # WebAuthn gem raises ArgumentError for malformed base64 in credential JSON
        raise Passkeys::VerificationFailed
      end
      notify_passkey_added
      render json: { redirect_to: settings_passkeys_path }, status: :created
    rescue Passkeys::Error => e
      render json: { error: t(e.i18n_key) }, status: :unprocessable_content
    end

    private

    # Best-effort, same contract as the new-device hook: a DB/queue hiccup
    # must not fail an enrollment that already succeeded.
    def notify_passkey_added
      PasskeyAddedNotifier.with(record: Current.user).deliver(Current.user)
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("[passkey-added] swallowed error for user=#{Current.user.id}: #{e.class}: #{e.message}")
    end
  end
end

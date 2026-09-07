# frozen_string_literal: true

module Passkeys
  module Registration
    # Second half of adding a passkey: the signed challenge becomes a
    # WebauthnCredential on the current user. Same gate as the challenge.
    class CredentialsController < ApplicationController
      before_action -> { require_reauthentication!(force: true) }

      def create
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
end

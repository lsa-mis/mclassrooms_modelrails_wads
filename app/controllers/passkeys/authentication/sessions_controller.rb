# frozen_string_literal: true

module Passkeys
  module Authentication
    # Second half of signing in with a passkey: the signed assertion becomes a
    # session. Rate-limited to slow brute-force attempts.
    class SessionsController < ApplicationController
      allow_unauthenticated_access
      rate_limit to: 10, within: 3.minutes, only: :create,
        with: -> { render json: { error: t("sessions.create.rate_limited") }, status: :too_many_requests }

      def create
        user = begin
          AuthenticateCeremony.verify(credential_params: params.to_unsafe_h)
        rescue ArgumentError
          # WebAuthn gem raises ArgumentError for malformed base64 in credential JSON
          raise Passkeys::VerificationFailed
        end
        start_new_session_for(user)
        render json: { redirect_to: after_authentication_url }
      rescue Passkeys::Error => e
        render json: { error: t(e.i18n_key) }, status: :unprocessable_content
      end
    end
  end
end

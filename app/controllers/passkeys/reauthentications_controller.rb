# frozen_string_literal: true

module Passkeys
  # Re-authenticate the CURRENT user with a passkey. Bound to Current.user: the
  # options only offer their credentials and verify rejects anyone else's, so a
  # passkey can confirm only its own owner's session.
  class ReauthenticationsController < ApplicationController
    def options
      render json: AuthenticateCeremony.options(user: Current.user, purpose: "reauthentication")
    end

    def verify
      begin
        AuthenticateCeremony.verify(
          credential_params: params.to_unsafe_h,
          expected_user: Current.user,
          purpose: "reauthentication"
        )
      rescue ArgumentError
        raise Passkeys::VerificationFailed
      end
      Current.session.confirm_reauthentication!
      render json: { redirect_to: reauthentication_return_to }
    rescue Passkeys::Error => e
      render json: { error: passkey_error_message(e) }, status: :unprocessable_content
    end
  end
end

# frozen_string_literal: true

module Passkeys
  module Reauthentication
    # Second half of confirming the current user with a passkey: the signed
    # assertion, bound to Current.user so a passkey can confirm only its own
    # owner's session, becomes a reauthentication on that session.
    class ConfirmationsController < ApplicationController
      def create
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
        render json: { error: t(e.i18n_key) }, status: :unprocessable_content
      end
    end
  end
end

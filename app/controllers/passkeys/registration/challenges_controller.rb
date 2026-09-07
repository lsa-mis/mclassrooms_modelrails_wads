# frozen_string_literal: true

module Passkeys
  module Registration
    # First half of adding a passkey: the challenge the authenticator will
    # sign. Authenticated, and reauthentication-gated even when reauth_enabled
    # is off, because the ceremony mints a durable credential and revokes
    # nothing. The second half is Registration::CredentialsController.
    class ChallengesController < ApplicationController
      before_action -> { require_reauthentication!(force: true) }

      def create
        render json: RegisterCeremony.options(user: Current.user)
      end
    end
  end
end

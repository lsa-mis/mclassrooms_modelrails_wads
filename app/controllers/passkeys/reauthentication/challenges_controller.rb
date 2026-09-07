# frozen_string_literal: true

module Passkeys
  module Reauthentication
    # First half of confirming the CURRENT user with a passkey: a challenge
    # that offers only their own credentials. The second half is
    # Reauthentication::ConfirmationsController.
    class ChallengesController < ApplicationController
      def create
        render json: AuthenticateCeremony.options(user: Current.user, purpose: "reauthentication")
      end
    end
  end
end

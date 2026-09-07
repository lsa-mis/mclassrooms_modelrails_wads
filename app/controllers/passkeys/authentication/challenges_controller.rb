# frozen_string_literal: true

module Passkeys
  module Authentication
    # First half of signing in with a passkey: an unauthenticated challenge.
    # The second half is Authentication::SessionsController.
    class ChallengesController < ApplicationController
      allow_unauthenticated_access

      def create
        render json: AuthenticateCeremony.options
      end
    end
  end
end

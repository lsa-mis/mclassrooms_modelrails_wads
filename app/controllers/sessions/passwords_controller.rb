module Sessions
  # The password step of email-first sign-in, reached from the check-email
  # page. Renders the form only; it posts to sessions#create.
  class PasswordsController < ApplicationController
    allow_unauthenticated_access

    def new
      @email_address = params[:email_address]
    end
  end
end

class MagicLinksController < ApplicationController
  allow_unauthenticated_access

  rate_limit to: 5, within: 3.minutes, only: :create,
    store: Rails.cache,
    with: -> { redirect_to new_session_path, alert: t("magic_links.create.rate_limited") }

  def create
    email = params[:email_address]&.downcase&.strip
    user = User.find_by(email_address: email)

    # Recipient throttle (SEC-9): shared :magic_link bucket with the lookup and
    # password-reset endpoints. Throttled requests fall through to the same
    # redirect without minting a token, so they can't supersede a live link.
    if user && EmailRecipientThrottle.allow!(user.email_address, kind: :magic_link)
      token = MagicLinkToken.create_for_email(user.email_address)
      MagicLinkMailer.sign_in_link(user.email_address, token).deliver_later if token
    end

    # Always show same message — no information leakage
    redirect_to new_session_path, notice: t(".check_email")
  end
end

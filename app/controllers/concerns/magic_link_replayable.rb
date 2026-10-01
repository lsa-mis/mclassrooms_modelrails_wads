# A redeemed token plus a live session for the same address is a replay; a superseded link the
# owner never clicked is not (#1083). Each caller decides what a replay says.
module MagicLinkReplayable
  extend ActiveSupport::Concern

  private

  # Takes the token as an argument: the two controllers name the param differently.
  def replayed_by_owner(token)
    return nil unless authenticated?

    spent = MagicLinkToken.find_spent(token)
    return nil unless spent&.redeemed?

    spent if spent.email == Current.user.email_address
  end
end

# A SPENT magic-link token plus a live session for THAT SAME address.
#
# "Spent" means `consumed_at` is set, which happens two ways: the token was
# redeemed, or a newer link superseded it unused. This module cannot tell them
# apart, and neither can its callers — giving redemption its own column is
# #1083. Every answer built on it therefore has to be true of BOTH, which is
# why a replay says "you are already signed in" and goes to the authenticated
# home rather than honouring an intent that may never have been acted on.
#
# A second presentation of a spent token is ordinary — a
# double-clicked confirm button, a browser retrying a POST, a re-clicked
# email, a prefetcher — and answering "invalid or has expired" tells a
# signed-in user the opposite of what just happened (#846 on the sign-in POST;
# the registration GET and POST had the same defect and no detection).
#
# Matching on the address is the fence: only the owner may read a spent token
# as their own replay. A signed-in visitor holding somebody else's used link
# still gets the invalid alert, and no session is started either way.
#
# Predicate-only, on purpose. The sign-in POST is shaped consume-first-then-
# branch (SEC-5) because a sign-in token must be spent either way; lifting
# that shape into a shared place would have the GET consuming on a mail
# scanner's bare fetch. This module reads and compares, nothing else — the
# caller decides what the replay answers, since a replayed registration says
# "welcome" and a replayed sign-in says "signed in".
module MagicLinkReplayable
  extend ActiveSupport::Concern

  private

  # The spent token belonging to this browser's address, or nil. Takes the
  # token as an argument because the two controllers name the param
  # differently — reading params in here would silently no-op for one of them.
  #
  # Every caller now reads this as a predicate. It still returns the record
  # because the row is what the address comparison is made of, not because
  # anyone routes on it.
  def replayed_by_owner(token)
    return nil unless authenticated?

    spent = MagicLinkToken.find_spent(token)
    return nil if spent.nil?

    spent if spent.email == Current.user.email_address
  end
end

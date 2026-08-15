# Single-use, expiry-guarded records consumed by an atomic compare-and-swap.
# Included by the token/challenge models (MagicLinkToken,
# ReauthenticationChallenge, WebauthnChallenge) that each stored the same
# consume mechanism by hand. Not for WorkspaceJoinLink — that is revoke-based
# and multi-use, a different lifecycle.
module Consumable
  extend ActiveSupport::Concern

  class_methods do
    # Atomic compare-and-swap: a single UPDATE guarded by `consumed_at IS NULL`
    # plus a live `expires_at`, so the database serializes concurrent consumers
    # and only one observes a row updated. Atomicity must live in the WHERE
    # clause, not a read-then-write — SQLite's per-connection lock does not
    # serialize across the Rails connection pool. Returns the number of rows
    # consumed (0 or 1); callers map that to a record or a boolean.
    def consume_matching(conditions)
      now = Time.current
      where(conditions.merge(consumed_at: nil))
        .where("expires_at > ?", now)
        .update_all(consumed_at: now)
    end
  end
end

# "This user operates the instance." Deliberately NOT a Membership and NOT a
# Role: memberships.workspace_id is null: false and Role(workspace_id: nil)
# already means "system default template", so neither can carry an
# instance-level grant without changing what it means.
class Operatorship < ApplicationRecord
  include Discardable

  belongs_to :user
  belongs_to :granted_by, class_name: "User", optional: true

  # STRICT audit grade (Trackable's vocabulary): the audit row commits with the
  # grant or neither does. Operatorship is a credential, like a passkey.
  def self.grant!(user:, granted_by: nil)
    transaction do
      create!(user: user, granted_by: granted_by).tap do |operatorship|
        ActivityLog.record_security_event!(
          action: "operatorship.granted", user: user, actor: granted_by,
          visibility: "admin", metadata: { operatorship_id: operatorship.id }
        )
      end
    end
  end

  # Idempotent: Discardable#discard! has no already-discarded guard, so a bare
  # call would push discarded_at forward and duplicate the audit row on a
  # second revoke! (double-submit, or two operators racing the same person) —
  # corrupting the one thing this credential-grade trail exists to get right.
  def revoke!(revoked_by: nil)
    return false if discarded?

    transaction do
      discard!
      ActivityLog.record_security_event!(
        action: "operatorship.revoked", user: user, actor: revoked_by,
        visibility: "admin", metadata: { operatorship_id: id }
      )
    end
    true
  end

  # Refuses the last kept operatorship and a self-revoke, reporting which
  # rule fired. Atomic on SQLite because BEGIN IMMEDIATE opens at this block's
  # first statement, so the count runs under the writer lock (`lock!` is only
  # a reload here) and a count of two or more followed by one discard cannot
  # reach zero. A Postgres fork needs an explicit lock — see
  # /docs/developer/architecture (Concurrency).
  def revoke_by_operator!(operator)
    transaction do
      lock!
      next :already_revoked if discarded?
      next :last_operator if Operatorship.kept.count <= 1
      next :self_revoke if operator == user

      revoke!(revoked_by: operator)
      :revoked
    end
  end
end

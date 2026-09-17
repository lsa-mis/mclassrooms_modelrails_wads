class User < ApplicationRecord
  # The reversible sign-in hold an operator places on an account.
  # See /docs/developer/security (Account suspension).
  module Suspension
    extend ActiveSupport::Concern

    def suspended? = suspended_at.present?

    # A credential-grade hold, not eviction: sign-in refused, sessions ended,
    # everything else (memberships, roles, project access) untouched, so
    # reinstating restores the person exactly. STRICT audit, like a passkey
    # change. Not built on Suspendable: that concern's rows are
    # workspace-domain best-effort via Trackable, and the spec pinning it
    # workspace-only stays true here.
    def suspend!(by:)
      transaction do
        lock!
        next :already_suspended if suspended?
        update!(suspended_at: Time.current)
        sessions.destroy_all
        ActivityLog.record_security_event!(action: "user.suspended", user: self, actor: by, visibility: "admin")
        :suspended
      end
    end

    def unsuspend!(by:)
      transaction do
        lock!
        next :not_suspended unless suspended?
        update!(suspended_at: nil)
        ActivityLog.record_security_event!(action: "user.unsuspended", user: self, actor: by, visibility: "admin")
        :unsuspended
      end
    end
  end
end

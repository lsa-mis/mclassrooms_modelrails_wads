class Workspace < ApplicationRecord
  # Who may come in, and on what terms: the admittability gate, the open-link
  # join policy, seat capacity, and the one membership-grant entry point.
  module Admission
    extend ActiveSupport::Concern

    # Derived from `status` so a future lifecycle state fails CLOSED here instead of silently admitting.
    def admittable?
      status == :active
    end

    def open_join?
      open_link? && !personal? && SignupPolicy.permits_strategy?(:open_link)
    end

    # SignupPolicy's gate checks open_join? only; admittable? is re-checked here at claim time.
    def accepting_open_joins?
      open_join? && admittable?
    end

    # `>=` here vs the after-create net's strict `>` — both deliberate. See /docs/developer/architecture (Concurrency).
    def at_capacity?
      memberships.kept.count >= max_members
    end

    # Pinned to the lowest-privilege system role; per-link role customization is deliberately deferred.
    def default_self_join_role
      Role.find_by!(slug: "member", workspace_id: nil)
    end

    # The one membership-grant entry point (invitations and open-link self-joins). granted_by: audit
    # provenance only; self_join: the joiner acted; on_existing: :raise or :adopt.
    # See /docs/developer/notifications (The actor rule) and /docs/developer/architecture (Authorization).
    def admit(user, role:, granted_by: nil, self_join: false, on_existing: :raise)
      Membership.reject_conflicting_provenance!(granted_by: granted_by, self_join: self_join)
      transaction do
        lock!
        raise NotAdmittableError unless admittable?
        existing = memberships.find_by(user: user)
        if existing&.discarded?
          existing.reactivate!(granted_by: granted_by, self_join: self_join)
          existing
        elsif existing
          raise AlreadyMember unless on_existing == :adopt || TenancyConfig.shared?
          # Rails runs commit callbacks on the LAST saved instance, so this second instance must carry
          # the markers too. See /docs/developer/notifications (The actor rule).
          existing.granted_by = granted_by
          existing.self_join = self_join
          if on_existing != :adopt && existing.role_id != role.id
            # :shared placeholder reconciliation — see /docs/developer/presets.
            existing.update!(role: role)
          end
          existing
        else
          raise AtCapacity if at_capacity?
          memberships.create!(user: user, role: role, granted_by: granted_by, self_join: self_join)
        end
      end
    end
  end
end

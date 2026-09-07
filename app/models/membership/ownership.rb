class Membership < ApplicationRecord
  # A membership's ownership semantics, and the owner floor the workspace defends:
  # the shared owner query, the last-owner invariants, and ownership transfer.
  # Race nets: /docs/developer/architecture (Concurrency).
  module Ownership
    extend ActiveSupport::Concern

    class_methods do
      # Kept owner-role memberships in the workspace, excluding the given
      # membership id — "are there OTHER owners besides this one?".
      def other_kept_owners(workspace_id, excluding:)
        kept.joins(:role)
            .merge(Role.owner)
            .where(workspace_id: workspace_id)
            .where.not(id: excluding)
      end
    end

    # Role identity only — deliberately silent on kept/discarded state; the
    # owner-floor queries carry their own kept filtering.
    def owner?
      role.present? && role.owner?
    end

    def transfer_ownership_to!(target_membership)
      owner_role = Role.system_default!("owner")
      admin_role = Role.system_default!("admin")

      transaction do
        workspace.lock!

        # CAS demote: zero rows means a racer demoted us first — abort before promoting. Skips callbacks
        # by design. See /docs/developer/architecture (Concurrency).
        rows = Membership.where(id: id)
                         .where(role_id: Role.owner.select(:id))
                         .update_all(role_id: admin_role.id)
        raise ActiveRecord::RecordInvalid, self if rows.zero?
        reload
        record_ownership_demotion(admin_role)

        target_membership.reload
        target_membership.update!(role: owner_role)
      end
    end

    private

    def validate_not_last_owner!
      if owner? && !Membership.other_kept_owners(workspace_id, excluding: id).exists?
        errors.add(:base, :last_owner)
        raise LastOwner, self
      end
    end

    # Post-discard race net. See /docs/developer/architecture (Concurrency).
    def enforce_owner_invariant!
      return unless owner?
      # Self is already discarded here, so "any kept owner" == "any OTHER kept
      # owner" — the shared query reads identically either way.
      return if Membership.other_kept_owners(workspace_id, excluding: id).exists?
      errors.add(:base, :last_owner)
      raise LastOwner, self
    end

    # Post-UPDATE owner-floor net. See /docs/developer/architecture (Concurrency).
    def enforce_owner_floor!
      # Self is already demoted here, so counting all kept owners == counting
      # the OTHER kept owners — the shared query reads identically either way.
      return if Membership.other_kept_owners(workspace_id, excluding: id).exists?
      errors.add(:base, :last_owner)
      raise LastOwner, self
    end

    # One of Trackable's named out-of-concern best-effort writers: the CAS demote skips callbacks, so the
    # audit row is written explicitly. The actor is the owner stepping down — this membership's own user —
    # never an ambient read (#1008). See /docs/developer/architecture (Actors are parameters).
    def record_ownership_demotion(to_role)
      ActivityLog.create!(
        actor: user,
        action: "membership.updated",
        trackable: self,
        workspace: workspace,
        visibility: "admin",
        metadata: { "changes" => { "role" => [ "owner", to_role.slug ] } }
      )
    rescue StandardError => e
      Rails.logger.warn("Activity tracking failed for Membership##{id} (transfer demote): #{e.message}")
      Rails.error.report(e, handled: true, context: { trackable: "Membership##{id}", action: "transfer_demote" })
    end

    # Self-exclusion is the contract: the very first owner being seeded
    # (User#create_personal_workspace, bootstrap) must not count as a pre-existing owner.
    def workspace_has_other_owners?
      return false if workspace_id.blank?
      Membership.other_kept_owners(workspace_id, excluding: id).exists?
    end
  end
end

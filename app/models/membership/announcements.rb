class Membership < ApplicationRecord
  # A membership announces its own transitions to the people they affect: role
  # changes, arrivals, re-admissions, removals, and the self-joiner's orientation.
  # Actor semantics: /docs/developer/notifications (The actor rule).
  module Announcements
    extend ActiveSupport::Concern

    included do
      # saved_change_to_role_id?, not role_id_previously_changed?: the latter lags under nested transactions.
      after_update_commit :notify_role_changed, if: :saved_change_to_role_id?

      after_create_commit :notify_member_added, if: :workspace_has_other_owners?

      # Re-admission is an UPDATE, so the create callback never sees it. Its own filter name is load-bearing:
      # the :commit chain dedups by filter and would REPLACE :notify_member_added. See /docs/developer/membership-lifecycle.
      after_update_commit :notify_member_readmitted, if: [ :just_reactivated?, :workspace_has_other_owners? ]

      after_update_commit :notify_member_removed, if: :just_deactivated?

      after_create_commit :notify_self_joined, if: :chosen_self_join?
      after_update_commit :notify_self_rejoined, if: [ :just_reactivated?, :chosen_self_join? ]
    end

    private

    # Fires post-commit: a raising notifier would 500 an action that already succeeded (#935). Same
    # swallow-log-report posture as Trackable#create_activity.
    def notify_best_effort(action)
      yield
    rescue StandardError => e
      Rails.logger.warn("Notification failed for Membership##{id} (#{action}): #{e.message}")
      Rails.error.report(e, handled: true, context: { trackable: "Membership##{id}", action: action })
    end

    def notify_role_changed
      notify_best_effort("role_changed") do
        next if user.blank?
        WorkspaceRoleChangedNotifier.with(record: self).deliver(user)
      end
    end

    # deliver(nil) and actor-as-param: see /docs/developer/notifications (The actor rule).
    def notify_member_added
      notify_best_effort("member_added") do
        next if user.blank? || workspace.blank?
        WorkspaceMemberAddedNotifier.with(record: self, actor: self_join ? user : granted_by).deliver(nil)
      end
    end

    alias_method :notify_member_readmitted, :notify_member_added

    def notify_member_removed
      notify_best_effort("member_removed") do
        next if user.blank? || workspace.blank?
        WorkspaceMemberRemovedNotifier.with(record: self, actor: removed_by).deliver(nil)
      end
    end

    # `deliver(nil)` again: WorkspaceJoinedNotifier declares a `recipients` block
    # so the in-app preference gate runs. An explicit recipient would skip it.
    def notify_self_joined
      notify_best_effort("self_joined") do
        next if user.blank? || workspace.blank?
        WorkspaceJoinedNotifier.with(record: self).deliver(nil)
      end
    end

    alias_method :notify_self_rejoined, :notify_self_joined
  end
end

# frozen_string_literal: true

# Fires when a Membership leaves the kept set — an owner removing someone, or
# a member removing themselves. The mirror of WorkspaceMemberAddedNotifier,
# and the transition that used to be silent: a removed member found out by
# hitting a wall (#933).
#
# Copy is per CHANNEL, not per reader. The in-app row is third-person
# event-log voice for everyone who receives it — the removed member reads the
# same sentence the owners do — and it branches on the EVENT: a member who
# removed themselves "left", anyone else "was removed". The email leg is the
# only second-person surface, and only the removed member ever gets one.
# See /docs/developer/notifications (Notifier subclasses).
class WorkspaceMemberRemovedNotifier < ApplicationNotifier
  # `account_access`, not `workspace_activity`, and the category is the whole
  # reason: it is the user's opt-out axis, and workspace_activity is the
  # chattiest one — every join, every workspace created. A member who had muted
  # it would learn they lost access to a workspace through neither channel,
  # which is the silence this notifier exists to end (#933). The nearest
  # precedent, WorkspaceRoleChangedNotifier, sits in the same category for the
  # same reason: it is a change to this person's access, not workspace news.
  category :account_access
  severity :warning
  record_preloads :user, :workspace

  recipients do
    removed_user = record.user

    # Same actor rule and same param discipline as the added-member sibling:
    # nobody is notified about their own action, and the actor rides as a
    # PARAM rather than off `record.removed_by`, which is a non-persisted
    # attr_accessor an exclusion could not rely on.
    candidates = ([ removed_user ] + record.workspace.owners).compact.uniq - [ params[:actor] ].compact
    permitted_in_app(candidates)
  end

  # Email goes to the removed member only. No self-removal check here: someone
  # who removed themselves is the actor, so the block above already dropped
  # them and no notification exists for this to run against.
  #
  # Both guards read columns and the already-loaded record, never `recipient`.
  # The first one narrows the fan-out to a single recipient, so the gate below
  # runs once however many owners there are — see the fan-out invariant in this
  # notifier's spec. Reading `recipient` instead would cost the same one load,
  # but Noticed's EventJob iterates `event.notifications.each`, and a lazy load
  # off a member of that collection is a shape Bullet raises on. The id
  # comparison has already established that the surviving recipient IS
  # `record.user`, which is what makes the second guard equivalent.
  deliver_by :email do |config|
    config.mailer = "NotificationMailer"
    config.method = :workspace_member_removed
    config.before_enqueue = lambda {
      throw(:abort) unless recipient_id == event.record.user_id
      throw(:abort) unless deliver_email_now_for?(event.record.user)
    }
    config.enqueue = true
  end

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.workspace_member_removed.#{self_removal? ? 'left' : 'removed'}",
          locale: recipient_locale,
          user_name: event.record.user.first_name,
          workspace: event.record.workspace.name
        )
      end
    end

    # The index, not the workspace. The workspace is exactly where the removed
    # member can no longer go — WorkspaceScoped answers that link with a
    # "not found" alert — and it is the one destination that stays true for
    # every recipient of this event. Reading nothing off the record also means
    # the deleted-record contract holds here by construction, with no rescue to
    # keep in step: there is nothing a vanished workspace can break.
    def url
      Rails.application.routes.url_helpers.workspaces_path
    end

    private

    # Compared by id, not by object: `params[:actor]` deserializes a GlobalID,
    # and `user_id` is a column already on the row.
    def self_removal?
      event.params[:actor]&.id == event.record.user_id
    end
  end
end

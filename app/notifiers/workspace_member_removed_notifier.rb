# frozen_string_literal: true

# A membership leaving the kept set: an owner removing someone, or a member leaving (#933).
# Category, copy and link choices: /docs/developer/notifications (Notifier subclasses).
class WorkspaceMemberRemovedNotifier < ApplicationNotifier
  # account_access, not workspace_activity: muting the chattiest category must not hide losing access.
  category :account_access
  severity :warning
  record_preloads :user, :workspace

  recipients do
    removed_user = record.user

    # The actor rides as a param, never record.removed_by. See /docs/developer/notifications (The actor rule).
    candidates = ([ removed_user ] + record.workspace.owners).compact.uniq - [ params[:actor] ].compact
    permitted_in_app(candidates)
  end

  # Removed member only; a self-remover is the actor and already dropped. Guards read columns, never
  # `recipient`: see /docs/developer/notifications (Email gating) and this notifier's fan-out spec.
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
          workspace_name: event.record.workspace.name
        )
      end
    end

    # The index, not the workspace the removed member can no longer reach; it reads nothing off the record.
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

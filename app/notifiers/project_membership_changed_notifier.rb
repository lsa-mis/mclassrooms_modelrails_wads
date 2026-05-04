# frozen_string_literal: true

class ProjectMembershipChangedNotifier < ApplicationNotifier
  category :project_activity

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t(
          "notifications.project_membership_changed.message",
          locale: recipient_locale,
          project: event.record.project.name,
          new_role: event.record.role.to_s.titleize
        )
      end
    end

    def url
      Rails.application.routes.url_helpers.project_path(event.record.project)
    end
  end
end

# frozen_string_literal: true

class NotificationPolicy < ApplicationPolicy
  # Collection-level predicates: any authenticated user is allowed to view
  # and act on their own notifications. Per-record isolation is enforced
  # by Scope (and by the controller's `Current.user.notifications.find`
  # for the per-record actions).
  def index?
    user.present?
  end

  def mark_all_read?
    user.present?
  end

  def destroy_all_read?
    user.present?
  end

  def update?
    record.recipient_id == user.id && record.recipient_type == "User"
  end

  def destroy?
    update?
  end

  # Bell-dropdown click — marks read + redirects to the notifier's URL.
  # Same recipient gate as update/destroy.
  def open?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(recipient: user)
    end
  end
end

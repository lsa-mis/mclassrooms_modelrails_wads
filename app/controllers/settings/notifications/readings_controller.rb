# frozen_string_literal: true

module Settings
  module Notifications
    # Open-and-mark-read as a POST-only resource (#686): creating the reading
    # marks the notification read (idempotently) and forwards to the
    # notifier's own URL. The old GET :open mutated on a safe verb, so link
    # prefetchers and mail scanners marked notifications read.
    class ReadingsController < ApplicationController
      def create
        notification = Current.user.notifications.find(params[:notification_id])
        authorize notification, :open?, policy_class: NotificationPolicy

        if notification.read_at.nil?
          notification.update!(read_at: Time.current)
          NotificationBroadcaster.refresh_for(
            Current.user, announcement_key: "notifications.bell.read_state_announcement"
          )
        end

        redirect_to notification.url
      end
    end
  end
end

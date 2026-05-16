require "rails_helper"

RSpec.describe NotificationBroadcaster do
  let(:user) { create(:user) }

  describe ".refresh_for" do
    it "broadcasts the avatar button label, bell indicator, menu count, and aria-live quartet for the given user" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        [ user, :notifications ],
        target: "notifications_avatar_button_label_frame",
        partial: "shared/user_menu_avatar_button_label",
        locals: hash_including(user: user, summary: hash_including(:count, :severity))
      )
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        [ user, :notifications ],
        target: "notifications_bell_indicator_frame",
        partial: "shared/notifications_bell",
        locals: hash_including(user: user, summary: hash_including(:count, :severity))
      )
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        [ user, :notifications ],
        target: "notifications_menu_count_frame",
        partial: "shared/notifications_menu_count_span",
        locals: hash_including(user: user, summary: hash_including(:count, :severity))
      )
      expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
        [ user, :notifications ],
        target: "notifications-live",
        content: I18n.t("notifications.bell.arrival_announcement")
      )

      described_class.refresh_for(user, announcement_key: "notifications.bell.arrival_announcement")
    end

    it "uses the announcement key to localize the aria-live content (e.g., read_state_announcement)" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
        [ user, :notifications ],
        target: "notifications-live",
        content: I18n.t("notifications.bell.read_state_announcement")
      )

      described_class.refresh_for(user, announcement_key: "notifications.bell.read_state_announcement")
    end

    # Performance contract: the unread breakdown query must fire EXACTLY
    # ONCE per refresh, even though four partials/broadcasts need the
    # summary. The broadcaster pre-computes it and passes it as a local.
    it "queries the unread breakdown only once and shares the summary across broadcasts" do
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)

      expect(user).to receive(:unread_notification_breakdown).once.and_call_original

      described_class.refresh_for(user, announcement_key: "notifications.bell.arrival_announcement")
    end

    # Inherits the same swallow-log-report contract documented on the
    # original broadcast site (PR #97). A broadcast adapter outage must
    # never propagate back to the caller (notifier callback or controller
    # action), but the failure must reach error tracking.
    it "swallows + logs + reports broadcast adapter errors so callers aren't blocked" do
      error = StandardError.new("cable down")
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(error)

      expect(Rails.logger).to receive(:warn).with(/cable down/).at_least(:once)
      expect(Rails.error).to receive(:report).with(error, hash_including(handled: true)).at_least(:once)

      expect {
        described_class.refresh_for(user, announcement_key: "notifications.bell.arrival_announcement")
      }.not_to raise_error
    end

    # Per-broadcast rescue: each surface is independent. A failure on the
    # FIRST broadcast must NOT abort the other three. Prevents the bell +
    # count + aria-live region from silently going stale when only the
    # avatar button label partial fails to render.
    it "continues other broadcasts when one fails (per-broadcast rescue)" do
      # First broadcast (avatar button label) raises; subsequent broadcasts
      # must still attempt.
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        anything, hash_including(target: "notifications_avatar_button_label_frame")
      ).and_raise(StandardError, "simulated cable failure")

      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        anything, hash_including(target: "notifications_bell_indicator_frame")
      ).at_least(:once)

      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        anything, hash_including(target: "notifications_menu_count_frame")
      ).at_least(:once)

      expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
        anything, hash_including(target: "notifications-live")
      ).at_least(:once)

      expect(Rails.logger).to receive(:warn).with(/notification broadcast failed.*avatar_button_label/)

      expect {
        described_class.refresh_for(user, announcement_key: "notifications.bell.arrival_announcement")
      }.not_to raise_error
    end
  end
end

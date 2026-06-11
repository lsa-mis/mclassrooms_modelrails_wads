require "rails_helper"

RSpec.describe "Notification Turbo Stream broadcasts" do
  let(:user) { create(:user) }

  it "broadcasts the v2 trio (avatar dot + hamburger dot + user-menu count row) to each recipient on event commit" do
    # All surfaces use broadcast_update_to now; allow the aria-live one (asserted
    # separately) so the three frame expectations below are the only constraints.
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
    expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
      [ a_kind_of(User), :notifications ],
      target: "notifications_indicator_avatar",
      partial: "shared/notifications_indicator",
      locals: hash_including(summary: hash_including(:count, :severity), surface: :avatar)
    )
    expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
      [ a_kind_of(User), :notifications ],
      target: "notifications_indicator_hamburger",
      partial: "shared/notifications_indicator",
      locals: hash_including(summary: hash_including(:count, :severity), surface: :hamburger)
    )
    expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
      [ a_kind_of(User), :notifications ],
      target: "notifications_menu_count_frame",
      partial: "shared/user_menu_notifications_row",
      locals: hash_including(user: a_kind_of(User), summary: hash_including(:count, :severity))
    )

    PasswordChangedNotifier.with(record: user).deliver(user)
  end

  it "broadcasts all four surfaces once per recipient when fanned out" do
    # 2 recipients × 4 surfaces (avatar dot + hamburger dot + menu count +
    # aria-live) = 8 update_to calls. v2 restored the menu-count broadcast that
    # D1 had dropped, because the user menu carries the canonical Notifications
    # link with a live count badge. All surfaces use broadcast_update_to so the
    # <turbo-frame> targets survive repeat refreshes.
    other = create(:user)

    expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).exactly(8).times

    PasswordChangedNotifier.with(record: user).deliver([ user, other ])
  end

  it "skips broadcasts when there are no User recipients" do
    # Recipients are Users in v1; no badge surface exists for non-User
    # streams, so a broadcast there is wasted work. The SQL-level filter
    # `recipient_type: "User"` makes recipient_ids empty for non-User
    # dispatches, and the guard short-circuits before any broadcast call.
    expect(Turbo::StreamsChannel).not_to receive(:broadcast_update_to)

    notifier = PasswordChangedNotifier.with(record: user)
    notifier.save!
    # Manually delete the auto-created User notification so the SQL filter
    # returns no rows.
    notifier.notifications.destroy_all
    notifier.send(:broadcast_notifications_arrival)
  end

  it "swallows broadcast adapter errors so notification creation isn't blocked" do
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to).and_raise(StandardError, "cable down")

    expect {
      PasswordChangedNotifier.with(record: user).deliver(user)
    }.not_to raise_error
  end

  # Panel-review blocker #1: bare `rescue StandardError` swallowed broadcast
  # errors silently. A genuine bug in the partial (e.g., a NoMethodError
  # introduced by a refactor) would disappear with zero signal to ops.
  # Swallow remains correct — notification creation must not block on a
  # broadcast outage — but the failure must reach error tracking.
  it "logs + reports broadcast errors so silent failures reach error tracking" do
    error = StandardError.new("cable down")
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to).and_raise(error)

    expect(Rails.logger).to receive(:warn).with(/cable down/).at_least(:once)
    expect(Rails.error).to receive(:report).with(error, hash_including(handled: true)).at_least(:once)

    PasswordChangedNotifier.with(record: user).deliver(user)
  end

  it "broadcasts an aria-live announcement update to the recipient" do
    # The frame surfaces also broadcast_update_to (different targets); allow them
    # so the specific aria-live expectation below is the only constraint.
    allow(Turbo::StreamsChannel).to receive(:broadcast_update_to)
    expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
      [ a_kind_of(User), :notifications ],
      target: "notifications-live",
      content: I18n.t("notifications.bell.arrival_announcement")
    )

    PasswordChangedNotifier.with(record: user).deliver(user)
  end
end

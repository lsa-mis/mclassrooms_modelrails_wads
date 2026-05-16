require "rails_helper"

RSpec.describe "Notification Turbo Stream broadcasts" do
  let(:user) { create(:user) }

  it "broadcasts the avatar-button-label + bell-indicator + menu-count quartet replaces to each recipient on event commit" do
    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
      [ a_kind_of(User), :notifications ],
      target: "notifications_avatar_button_label_frame",
      partial: "shared/user_menu_avatar_button_label",
      locals: hash_including(user: a_kind_of(User), summary: hash_including(:count, :severity))
    )
    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
      [ a_kind_of(User), :notifications ],
      target: "notifications_bell_indicator_frame",
      partial: "shared/notifications_bell",
      locals: hash_including(user: a_kind_of(User), summary: hash_including(:count, :severity))
    )
    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
      [ a_kind_of(User), :notifications ],
      target: "notifications_menu_count_frame",
      partial: "shared/notifications_menu_count_span",
      locals: hash_including(user: a_kind_of(User), summary: hash_including(:count, :severity))
    )

    PasswordChangedNotifier.with(record: user).deliver(user)
  end

  it "broadcasts all three frames once per recipient when fanned out" do
    # 2 recipients × 3 frames (avatar-button + bell-indicator + menu-count) = 6 total replaces.
    other = create(:user)

    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).exactly(6).times

    PasswordChangedNotifier.with(record: user).deliver([ user, other ])
  end

  it "skips broadcasts when there are no User recipients" do
    # Recipients are Users in v1; no badge surface exists for non-User
    # streams, so a broadcast there is wasted work. The SQL-level filter
    # `recipient_type: "User"` makes recipient_ids empty for non-User
    # dispatches, and the guard short-circuits before any broadcast call.
    expect(Turbo::StreamsChannel).not_to receive(:broadcast_replace_to)

    notifier = PasswordChangedNotifier.with(record: user)
    notifier.save!
    # Manually delete the auto-created User notification so the SQL filter
    # returns no rows.
    notifier.notifications.destroy_all
    notifier.send(:broadcast_notifications_arrival)
  end

  it "swallows broadcast adapter errors so notification creation isn't blocked" do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(StandardError, "cable down")

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
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to).and_raise(error)

    expect(Rails.logger).to receive(:warn).with(/cable down/).at_least(:once)
    expect(Rails.error).to receive(:report).with(error, hash_including(handled: true)).at_least(:once)

    PasswordChangedNotifier.with(record: user).deliver(user)
  end

  it "broadcasts an aria-live announcement update to the recipient" do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    expect(Turbo::StreamsChannel).to receive(:broadcast_update_to).with(
      [ a_kind_of(User), :notifications ],
      target: "notifications-live",
      content: I18n.t("notifications.bell.arrival_announcement")
    )

    PasswordChangedNotifier.with(record: user).deliver(user)
  end
end

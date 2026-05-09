require "rails_helper"

RSpec.describe "Notification Turbo Stream broadcasts" do
  let(:user) { create(:user) }

  it "broadcasts a bell-frame replace to each recipient on event commit" do
    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
      [ a_kind_of(User), :notifications ],
      target: "notifications_bell_frame",
      partial: "shared/notifications_bell_button",
      locals: { user: a_kind_of(User) }
    )

    PasswordChangedNotifier.with(record: user).deliver(user)
  end

  it "broadcasts once per recipient when fanned out" do
    other = create(:user)

    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).twice

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

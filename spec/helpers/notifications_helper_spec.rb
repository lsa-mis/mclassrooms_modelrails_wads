require "rails_helper"

RSpec.describe NotificationsHelper, type: :helper do
  let(:user) { create(:user) }

  # The helper eager-loads `event: :record` for the bell dropdown view, which
  # reads each notification's #message. These unit examples assert only the
  # limit/merge/sort logic on ids and timestamps and never render, so Bullet's
  # unused-eager-loading check false-positives — scope it off for this file.
  around do |example|
    if defined?(Bullet) && Bullet.enable?
      original = Bullet.unused_eager_loading_enable?
      Bullet.unused_eager_loading_enable = false
      begin
        example.run
      ensure
        Bullet.unused_eager_loading_enable = original
      end
    else
      example.run
    end
  end

  # Delivers one real Noticed notification to `recipient` and returns the
  # record, optionally marking it read and/or backdating it so the
  # limit/merge/sort behavior can be exercised deterministically. A unique
  # idempotency_key per call defeats Noticed's deduplication — otherwise
  # repeated PasswordChangedNotifier deliveries with identical params collapse
  # into a single notification (see spec/models/user_spec.rb).
  def deliver_notification(recipient, read: false, created_at: nil)
    @delivery_seq = (@delivery_seq || 0) + 1
    PasswordChangedNotifier.with(record: recipient, idempotency_key: "test-#{@delivery_seq}").deliver(recipient)
    notification = recipient.notifications.order(:id).last
    attrs = {}
    attrs[:read_at] = Time.current if read
    attrs[:created_at] = created_at if created_at
    notification.update_columns(attrs) unless attrs.empty?
    notification
  end

  describe "#recent_notifications_for_dropdown" do
    it "returns an empty array when the user has no notifications" do
      expect(helper.recent_notifications_for_dropdown(user)).to eq([])
    end

    it "caps unread at 10 and read at 5" do
      11.times { deliver_notification(user) }
      6.times { deliver_notification(user, read: true) }

      result = helper.recent_notifications_for_dropdown(user)

      expect(result.count { |n| n.read_at.nil? }).to eq(NotificationsHelper::RECENT_UNREAD_LIMIT)
      expect(result.count { |n| n.read_at.present? }).to eq(NotificationsHelper::RECENT_READ_LIMIT)
      expect(result.size).to eq(15)
    end

    it "merges unread and read, ordered newest-first" do
      older_read = deliver_notification(user, read: true, created_at: 3.hours.ago)
      middle_unread = deliver_notification(user, created_at: 1.hour.ago)
      newest_unread = deliver_notification(user, created_at: 1.minute.ago)

      result = helper.recent_notifications_for_dropdown(user)

      expect(result.map(&:id)).to eq([ newest_unread.id, middle_unread.id, older_read.id ])
    end

    it "keeps the newest unread when over the unread limit" do
      oldest = deliver_notification(user, created_at: 1.day.ago)
      11.times { |i| deliver_notification(user, created_at: (i + 1).minutes.ago) }

      result = helper.recent_notifications_for_dropdown(user)

      expect(result.map(&:id)).not_to include(oldest.id)
    end

    it "scopes to the given user" do
      mine = deliver_notification(user)
      deliver_notification(create(:user))

      result = helper.recent_notifications_for_dropdown(user)

      expect(result.map(&:id)).to eq([ mine.id ])
    end
  end
end

class Session < ApplicationRecord
  belongs_to :user

  validates :ip_address, length: { maximum: 45 }, allow_nil: true
  validates :user_agent, length: { maximum: 512 }, allow_nil: true

  # A session is dead once it has been idle past the idle timeout OR has simply
  # existed past the absolute timeout. `last_active_at` is backfilled to now for
  # pre-existing rows, but stays nil-safe here so a session created outside
  # start_new_session_for (e.g. a test fixture) never raises on the comparison.
  scope :active, -> {
    where("last_active_at IS NULL OR last_active_at > ?", idle_timeout.ago)
      .where("created_at > ?", absolute_timeout.ago)
  }
  scope :expired, -> {
    where("(last_active_at IS NOT NULL AND last_active_at <= ?) OR created_at <= ?",
          idle_timeout.ago, absolute_timeout.ago)
  }

  def self.idle_timeout = Rails.configuration.x.session.idle_timeout
  def self.absolute_timeout = Rails.configuration.x.session.absolute_timeout
  def self.touch_throttle = Rails.configuration.x.session.touch_throttle

  def expired?
    (last_active_at || created_at) <= self.class.idle_timeout.ago ||
      created_at <= self.class.absolute_timeout.ago
  end

  # Refresh last_active_at, but keep the write off the SQLite single-writer hot
  # path: the in-memory guard means a request inside the throttle window never
  # touches the writer lock at all. When stale, a single conditional UPDATE (the
  # predicate lives in the WHERE, mirroring MagicLinkToken.consume!) collapses
  # two racing requests to at most one effective write.
  def touch_last_active!
    throttle = self.class.touch_throttle
    return if last_active_at && last_active_at > throttle.ago

    self.class.where(id: id)
        .where("last_active_at IS NULL OR last_active_at < ?", throttle.ago)
        .update_all(last_active_at: Time.current)
  end

  # Coarse "Browser on OS" label for the active-devices list. Deliberately
  # simple — enough for a user to recognize their own device, not forensic UA
  # parsing.
  def device_label
    ua = user_agent.to_s
    browser =
      case ua
      when /Edg/ then "Edge"
      when /Chrome|CriOS/ then "Chrome"
      when /Firefox|FxiOS/ then "Firefox"
      when /Safari/ then "Safari"
      end
    os =
      case ua
      when /iPhone|iPad|iPod/ then "iOS"
      when /Android/ then "Android"
      when /Windows/ then "Windows"
      when /Macintosh|Mac OS X/ then "macOS"
      when /Linux/ then "Linux"
      end
    [ browser, os ].compact.join(" on ").presence || "Unknown device"
  end
end

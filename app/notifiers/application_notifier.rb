# frozen_string_literal: true

class ApplicationNotifier < Noticed::Event
  class_attribute :category_name, instance_accessor: false

  def self.category(name)
    self.category_name = name.to_s
  end

  before_create :populate_idempotency_key

  notification_methods do
    def recipient_pref(channel)
      preferences_object.allow?(category: event.class.category_name, channel: channel.to_s)
    end

    def recipient_locale
      recipient.try(:preferences)&.locale.presence&.to_sym || I18n.default_locale
    end

    def mark_seen!
      return if seen_at.present?
      update_column(:seen_at, Time.current)
    end

    # Wrap any Notifier message/url body that traverses associations or
    # accesses attributes on the resource. Catches:
    #   - ActiveRecord::RecordNotFound (e.g., resource was destroyed mid-render)
    #   - NoMethodError on nil receiver (e.g., a chained association is now nil)
    # Real bugs (typos, missing methods on non-nil receivers) propagate.
    #
    # Note: only deletion shapes where Ruby raises with a *nil* receiver are
    # caught. If your message accesses `resource.invitable.name` and the
    # `invitable` is gone, the call to `.name` on nil raises NoMethodError
    # with receiver=nil — caught. Other deletion patterns (stale FK pointing
    # to a deleted record that still loads as a stub object) won't trigger
    # nil-receiver and may bubble up as RecordNotFound or other exceptions.
    def render_safe_or_placeholder
      yield
    rescue ActiveRecord::RecordNotFound
      Rails.logger.info("Notification ##{id} references deleted record; rendering placeholder")
      I18n.t("notifications.placeholder")
    rescue NoMethodError => e
      raise unless e.receiver.nil?
      Rails.logger.info("Notification ##{id} references deleted record; rendering placeholder")
      I18n.t("notifications.placeholder")
    end

    private

    def preferences_object
      recipient.try(:preferences)&.notification_preferences_object || NotificationPreferences.new(nil)
    end
  end

  # Override deliver to return sentinel :delivered on first-send or :deduplicated
  # on RecordNotUnique rescue. The DB partial unique index on noticed_events
  # (idempotency_key) is the atomic source of truth for concurrent dispatch;
  # this rescue is the real backstop, not dead code.
  #
  # No app-level SELECT-then-INSERT fast-path: that pattern was a TOCTOU race
  # in the previous implementation. The DB constraint enforces atomically.
  def deliver(recipients = nil, **options)
    super
    :delivered
  rescue ActiveRecord::RecordNotUnique
    :deduplicated
  end

  private

  # Populates noticed_events.idempotency_key from the polymorphic `record`
  # that Noticed assigns from `with(record: ...)`. Noticed strips :record
  # from params before validation, so we read self.record (the association)
  # rather than params[:record]. Pass an explicit `idempotency_key:` to
  # override when the natural record id isn't the right dedup seed.
  #
  # Raises ArgumentError if neither :record nor an explicit key is supplied.
  # Loud failure beats silent dedup-collapse across distinct events.
  def populate_idempotency_key
    return if idempotency_key.present?

    explicit_key = params[:idempotency_key] || params["idempotency_key"]
    if explicit_key.present?
      self.idempotency_key = explicit_key
      return
    end

    seed_id = record.try(:id) || record.try(:to_gid_param)

    if seed_id.blank?
      raise ArgumentError,
        "#{self.class.name} requires either a :record with an id, or an explicit :idempotency_key"
    end

    # One-minute bucket is the documented dedup window. Cross-boundary
    # dispatches (one at second 59, retry at second 0 of next minute) get
    # different keys and BOTH succeed. This is intentional — coalescing
    # beyond a minute is digest territory, not idempotency.
    self.idempotency_key = "#{self.class.name}_#{seed_id}_#{Time.current.to_i / 60}"
  end
end

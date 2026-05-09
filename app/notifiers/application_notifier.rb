# frozen_string_literal: true

class ApplicationNotifier < Noticed::Event
  class_attribute :category_name, instance_accessor: false

  def self.category(name)
    self.category_name = name.to_s
  end

  before_create :populate_idempotency_key

  # Broadcast a Turbo Stream replacing the bell frame to each recipient's
  # `[user, :notifications]` stream after the event's transaction commits.
  # Hooks here (on the Event) rather than on Noticed::Notification because
  # Noticed v2 uses `notifications.insert_all!` which bypasses callbacks on
  # the Notification class. By the time this `after_create_commit` fires,
  # the bulk-inserted notification rows are already persisted and the page
  # can pick up fresh state.
  after_create_commit :broadcast_notifications_arrival

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

    # Delegates to ApplicationNotifier#preferences_for so per-recipient
    # gating in `recipient_pref` shares the same fallback semantic that
    # event-level resolvers use. See ApplicationNotifier#preferences_for
    # for the missing-prefs rationale.
    def preferences_object
      ApplicationNotifier.preferences_for(recipient)
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

  # Resolve a NotificationPreferences object for any user, including users
  # without a persisted UserPreferences row.
  #
  # Why a transient `UserPreferences.new` for the missing-prefs case?
  # The `user_preferences.notification_preferences` JSONB column has a
  # database-level default that contains the canonical permission matrix
  # (see db/schema.rb). Reading it via `UserPreferences.new.notification_preferences`
  # honors that single source of truth — Rails populates the column default
  # on the in-memory record. Hard-coding the matrix in Ruby would create a
  # second copy that could silently drift from the schema default.
  #
  # The previous behavior wrapped `nil`, which made every category except
  # `security` return false from `NotificationPreferences#allow?`. That
  # produced a silent default-deny posture for freshly-created users with
  # no preferences row yet — incorrect, since the schema default permits
  # in-app delivery for every category.
  #
  # Available as both a class method (used by the per-recipient
  # `recipient_pref` shim defined inside `notification_methods`) and an
  # instance method (used by class-level `recipients` resolvers).
  def self.preferences_for(user)
    persisted = user.try(:preferences)
    if persisted&.notification_preferences.present?
      persisted.notification_preferences_object
    else
      NotificationPreferences.new(UserPreferences.new.notification_preferences)
    end
  end

  def preferences_for(user)
    self.class.preferences_for(user)
  end

  # Returns the per-notification STI `type` strings for every Notifier
  # subclass in the given category — i.e. the values stored in
  # `noticed_notifications.type` (e.g. "PasswordChangedNotifier::Notification").
  # Use this when filtering Noticed::Notification scopes by category.
  #
  # Returns raw class names without the `::Notification` suffix when you
  # need the parent Notifier identity instead — see `.notifier_class_names_for`.
  #
  # The `::Notification` suffix is the Noticed-internal STI shape produced
  # by `notification_methods do ... end` — keeping that detail localized
  # here, near the rest of the Notifier scaffolding.
  def self.notification_types_for(category)
    notifier_class_names_for(category).map { |name| "#{name}::Notification" }
  end

  # Returns raw Notifier class-name strings (no STI suffix) for the given
  # category. Use this when keying off the parent Notifier (event.type),
  # e.g. retention floors or analytics rollups.
  def self.notifier_class_names_for(category)
    target = category.to_s
    descendants.select { |c| c.category_name == target }.map(&:name)
  end

  private

  def broadcast_notifications_arrival
    # Query `Noticed::Notification` directly (not `self.notifications`) so
    # the parent-child `inverse_of` link doesn't make Bullet think `event`
    # is preloaded for every Notification subtype — false-AVOID-warning
    # noise across every spec that dispatches a notifier. The SQL is the
    # same; we lose the auto-set parent reference we don't use anyway.
    recipient_ids = Noticed::Notification
                      .where(event_id: id, recipient_type: "User")
                      .pluck(:recipient_id)
    return if recipient_ids.empty?

    User.where(id: recipient_ids).find_each do |user|
      Turbo::StreamsChannel.broadcast_replace_to(
        [ user, :notifications ],
        target: "notifications_bell_frame",
        partial: "shared/notifications_bell_button",
        locals: { user: user }
      )

      # Drop the announcement into the page-level aria-live region so the
      # arrival is narrated by assistive tech without competing for focus.
      # `polite` + `atomic` (set on the slot itself) re-reads the full
      # message every time it changes.
      Turbo::StreamsChannel.broadcast_update_to(
        [ user, :notifications ],
        target: "notifications-live",
        content: I18n.t("notifications.bell.arrival_announcement")
      )
    end
  rescue StandardError
    # Same rationale as `Broadcastable`: a broadcast adapter outage must
    # never block notification creation. The notification rows still
    # persist; the user picks up the new badge on next page load.
  end

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

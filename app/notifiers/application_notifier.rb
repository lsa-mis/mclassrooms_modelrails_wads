# frozen_string_literal: true

class ApplicationNotifier < Noticed::Event
  # Always a String — the `category` DSL coerces on write.
  class_attribute :category_name, instance_accessor: false

  # Always a Symbol — the `severity` DSL coerces and validates on write.
  class_attribute :severity_name, instance_accessor: false, default: :info

  # Canonical severity set consumed by UnreadNotificationSummary
  # (SEVERITY_RANK) and NotificationBellHelper (SEVERITY_CLASSES). Any value
  # declared via `severity :foo` MUST be one of these — otherwise the
  # summary's `SEVERITY_RANK.fetch(_1)` raises KeyError at render time, far
  # from the typo's source.
  VALID_SEVERITIES = %i[danger warning info success].freeze

  # Bucket segment generators for the idempotency key, keyed by the
  # granularity a subclass declares via `dedup_bucket`. The :minute default
  # is the documented one-minute dedup window; :day collapses sweep-driven
  # re-dispatches to one notification per day.
  DEDUP_BUCKETS = {
    minute: -> { Time.current.to_i / 60 },
    day: -> { Time.current.to_date.iso8601 }
  }.freeze

  # Declared via the `dedup_bucket` / `dedup_seed` DSL below; consumed by
  # populate_idempotency_key — the ONE place keys are assembled.
  class_attribute :dedup_bucket_granularity, instance_accessor: false, default: :minute
  class_attribute :dedup_seed_block, instance_accessor: false, default: nil

  def self.category(name)
    self.category_name = name.to_s
  end

  # Declares a severity for this Notifier. Raises at class-load time on an
  # unknown value so typos fail loud at boot rather than silently storing a
  # bad symbol and exploding later at render. See VALID_SEVERITIES above.
  def self.severity(name)
    symbol = name.to_sym
    unless VALID_SEVERITIES.include?(symbol)
      raise ArgumentError,
        "Invalid severity #{name.inspect} for #{self.name}. " \
        "Must be one of: #{VALID_SEVERITIES.map(&:inspect).join(', ')}."
    end
    self.severity_name = symbol
  end

  # Declares the idempotency-key time bucket for this Notifier. Raises at
  # class-load time on an unknown granularity — same fail-loud posture as
  # `severity`.
  def self.dedup_bucket(granularity)
    symbol = granularity.to_sym
    unless DEDUP_BUCKETS.key?(symbol)
      raise ArgumentError,
        "Invalid dedup bucket #{granularity.inspect} for #{name}. " \
        "Must be one of: #{DEDUP_BUCKETS.keys.map(&:inspect).join(', ')}."
    end
    self.dedup_bucket_granularity = symbol
  end

  # Declares an extra key segment (or array of segments) contributed between
  # the record id and the time bucket. The block is instance-exec'd on the
  # event, so it can read `params` and `record` — e.g.
  # `dedup_seed { params[:metric] }` scopes dedup per (record, metric).
  def self.dedup_seed(&block)
    self.dedup_seed_block = block
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
    # Tri-state delivery report for a channel: true (deliver now), false
    # (dropped), or :digest (email queued for the digest pipeline). Kept as
    # an introspection surface — per-notifier specs pin channel gating
    # through it. App code never branches on the sentinel: the delivery
    # gates below use the strict deliver_now? predicate directly.
    def recipient_pref(channel)
      category = event.class.category_name
      return :digest if preferences_object.defer_to_digest?(category: category, channel: channel)
      preferences_object.deliver_now?(category: category, channel: channel)
    end

    # The email gate for `deliver_by :email` before_enqueue hooks. Strictly
    # "send the instant email now" — opted out, DND, and deferred-to-digest
    # all abort.
    # See /docs/developer/notifications (Email gating and the `:digest` sentinel).
    def deliver_email_now?
      preferences_object.deliver_now?(category: event.class.category_name, channel: :email)
    end

    def recipient_locale
      stored = recipient.try(:preferences)&.locale.presence&.to_sym
      # Guard the availability check rather than trusting the column: rows
      # written before UserPreferences validated this, or a fork retiring a
      # language it once shipped, would otherwise hand an unsupported locale
      # to I18n.t. That raises I18n::InvalidLocale, which
      # render_safe_or_placeholder does not rescue — the bell 500s.
      return I18n.default_locale unless stored && I18n.available_locales.include?(stored)
      stored
    end

    def mark_seen!
      return if seen_at.present?
      update_column(:seen_at, Time.current)
    end

    # Wrap Notifier message/url bodies. Rescues only deletion shapes —
    # RecordNotFound and NoMethodError with a *nil* receiver; real bugs on
    # non-nil receivers propagate.
    # See /docs/developer/notifications (render_safe_or_placeholder — the deleted-record contract).
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

  # Resolve a NotificationPreferences object for any user. Missing-prefs users
  # get a transient `UserPreferences.new` so the schema-default JSONB blob stays
  # the single source of truth (wrapping `nil` silently default-denied new users).
  # See /docs/developer/notifications (Preference resolution and the missing-row fallback).
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

  # Shared recipient gate for `recipients do ... end` blocks: preloads
  # :preferences for the whole candidate set in ONE query (`preferences_for`
  # reads `user.preferences` per-user — an N+1 without the preload; Bullet
  # caught the original in the Reshape 2a open-link self-join request specs),
  # then keeps only users whose preferences allow this class's declared
  # category on the in_app channel. Uses `category_name` from the `category`
  # DSL so subclasses never restate their category as a string literal.
  def permitted_in_app(candidates)
    ActiveRecord::Associations::Preloader.new(records: candidates, associations: :preferences).call
    candidates.select do |user|
      preferences_for(user).deliver_now?(category: self.class.category_name, channel: "in_app")
    end
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

    # NotificationBroadcaster handles the four broadcast targets AND the
    # swallow-log-report contract for adapter outages. Per-user iteration so one
    # bad broadcast doesn't poison the rest — each call is self-rescuing.
    User.where(id: recipient_ids).find_each do |user|
      NotificationBroadcaster.refresh_for(user, announcement_key: "notifications.bell.arrival_announcement")
    end
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

    # Cross-boundary dispatches (one at second 59 of a minute bucket, retry
    # at second 0 of the next) get different keys and BOTH succeed. This is
    # intentional — coalescing beyond the declared bucket is digest
    # territory, not idempotency.
    segments = [ self.class.name, seed_id ]
    segments.concat(Array(instance_exec(&self.class.dedup_seed_block))) if self.class.dedup_seed_block
    segments << instance_exec(&DEDUP_BUCKETS.fetch(self.class.dedup_bucket_granularity))
    self.idempotency_key = segments.join("_")
  end
end

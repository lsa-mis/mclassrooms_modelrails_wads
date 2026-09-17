# frozen_string_literal: true

class ApplicationNotifier < Noticed::Event
  # Always a String — the `category` DSL coerces on write.
  class_attribute :category_name, instance_accessor: false

  # Always a Symbol — the `severity` DSL coerces and validates on write.
  class_attribute :severity_name, instance_accessor: false, default: :info

  # Must stay in sync with UnreadNotificationSummary::SEVERITY_RANK and
  # NotificationBellHelper::SEVERITY_CLASSES — an unlisted value raises
  # KeyError at render time, far from the typo.
  VALID_SEVERITIES = %i[danger warning info success].freeze

  # :day collapses sweep-driven re-dispatches to one notification per day.
  DEDUP_BUCKETS = {
    minute: -> { Time.current.to_i / 60 },
    day: -> { Time.current.to_date.iso8601 }
  }.freeze

  class_attribute :dedup_bucket_granularity, instance_accessor: false, default: :minute
  class_attribute :dedup_seed_block, instance_accessor: false, default: nil

  class_attribute :record_preload_spec, instance_accessor: false, default: [].freeze

  def self.category(name)
    self.category_name = name.to_s
  end

  def self.severity(name)
    symbol = name.to_sym
    unless VALID_SEVERITIES.include?(symbol)
      raise ArgumentError,
        "Invalid severity #{name.inspect} for #{self.name}. " \
        "Must be one of: #{VALID_SEVERITIES.map(&:inspect).join(', ')}."
    end
    self.severity_name = symbol
  end

  def self.dedup_bucket(granularity)
    symbol = granularity.to_sym
    unless DEDUP_BUCKETS.key?(symbol)
      raise ArgumentError,
        "Invalid dedup bucket #{granularity.inspect} for #{name}. " \
        "Must be one of: #{DEDUP_BUCKETS.keys.map(&:inspect).join(', ')}."
    end
    self.dedup_bucket_granularity = symbol
  end

  # Instance-exec'd on the event, so the block can read `params` and `record`.
  def self.dedup_seed(&block)
    self.dedup_seed_block = block
  end

  # Must stay in sync with what this notifier's `#message` reads:
  # notifications_record_preloads_spec fails on a missing AND a superfluous
  # entry. See /docs/developer/notifications (Notifier subclasses).
  def self.record_preloads(*associations)
    self.record_preload_spec = associations.freeze
  end

  # Skipping a class that lacks the association is what makes a polymorphic
  # hop expressible (Invitation#invitable → Project#workspace, where a
  # Workspace invitable has no `workspace`).
  def self.preload_records(notifications)
    notifications.group_by { |notification| notification.event.type }.each_value do |group|
      event_class = group.first.event.class
      next unless event_class.respond_to?(:record_preload_spec)

      spec = event_class.record_preload_spec
      next if spec.empty?

      preload_tree(group.map { |notification| notification.event.record }.compact, spec)
    end
  end

  def self.preload_tree(records, spec)
    records.group_by(&:class).each do |klass, group|
      Array(spec).each do |entry|
        case entry
        when Hash
          entry.each do |association, nested|
            next unless preload_association(klass, group, association)

            preload_tree(group.flat_map { |record| Array(record.public_send(association)) }.compact, nested)
          end
        else
          preload_association(klass, group, entry)
        end
      end
    end
  end
  private_class_method :preload_tree

  def self.preload_association(klass, records, association)
    return false unless klass.reflect_on_association(association)

    ActiveRecord::Associations::Preloader.new(records: records, associations: association).call
    true
  end
  private_class_method :preload_association

  before_create :populate_idempotency_key

  # On the Event, not Noticed::Notification, which never fires its callbacks.
  # See /docs/developer/notifications (Why hook on `Noticed::Event`).
  after_create_commit :broadcast_notifications_arrival

  notification_methods do
    # Unused by app code and kept deliberately: per-notifier specs pin channel
    # gating through it. Delivery gates use the strict predicates below.
    def recipient_pref(channel)
      category = event.class.category_name
      return :digest if preferences_object.defer_to_digest?(category: category, channel: channel)
      preferences_object.deliver_now?(category: category, channel: channel)
    end

    # See /docs/developer/notifications (Email gating and the `:digest` sentinel).
    def deliver_email_now?
      event.email_permitted?(recipient_id)
    end

    def deliver_email_now_for?(user)
      event.deliver_email_now_for?(user)
    end

    def recipient_locale
      stored = recipient.try(:preferences)&.locale.presence&.to_sym
      # Check availability rather than trusting the column: an unsupported
      # locale raises I18n::InvalidLocale, which render_safe_or_placeholder
      # does not rescue, and the bell 500s.
      return I18n.default_locale unless stored && I18n.available_locales.include?(stored)
      stored
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

    # Call this in every `#url` body: a nil reaching a route helper raises
    # UrlGenerationError, which render_safe_or_placeholder does not rescue, and
    # one dead row takes down that user's entire digest. `#message` bodies do
    # not need it — they dereference the record and raise NoMethodError first.
    def present_or_gone!(record)
      raise ActiveRecord::RecordNotFound if record.nil?
      record
    end

    private

    def preferences_object
      ApplicationNotifier.preferences_for(recipient)
    end
  end

  # Three traps, all load-bearing. Do not add a SELECT-then-INSERT fast-path:
  # the unique index is the atomic source of truth and the rescue is the real
  # backstop, not dead code. Do not move the empty-set guard into `super`: the
  # gem saves the event row unconditionally, which burns the idempotency key on
  # a dispatch nobody received. Do not resolve recipients twice: the array is
  # handed to `super` so a `recipients` block runs exactly once per dispatch.
  # See /docs/developer/notifications (Idempotency).
  def deliver(recipients = nil, **options)
    resolved = Array.wrap(recipients || evaluate_recipients)
    return :skipped if resolved.empty?

    super(resolved, **options)
    :delivered
  rescue ActiveRecord::RecordNotUnique
    :deduplicated
  end

  # A missing row falls back to a transient `UserPreferences.new`, not nil —
  # wrapping nil default-denies every new user.
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

  # See /docs/developer/notifications (Email gating and the `:digest` sentinel).
  def deliver_email_now_for?(user)
    preferences_for(user).deliver_now?(category: self.class.category_name, channel: :email)
  end

  # Ids, not a Preloader over the notification rows: the eager `recipient` goes
  # unread wherever an email leg narrows to one recipient, and Bullet raises on
  # that in test. See /docs/developer/notifications (Email gating and the
  # `:digest` sentinel).
  def email_permitted?(recipient_id)
    email_permitted_recipient_ids.include?(recipient_id)
  end

  # The preload is not optional: `preferences_for` reads `user.preferences`
  # per user, which is an N+1 without it.
  # See /docs/developer/notifications (In-app gating lives in `recipients`).
  def permitted_in_app(candidates)
    ActiveRecord::Associations::Preloader.new(records: candidates, associations: :preferences).call
    candidates.select do |user|
      preferences_for(user).deliver_now?(category: self.class.category_name, channel: "in_app")
    end
  end

  # The `::Notification` suffix is Noticed's STI shape, produced by
  # `notification_methods`. Filter Noticed::Notification scopes with these;
  # key off the parent Notifier with `.notifier_class_names_for`.
  def self.notification_types_for(category)
    notifier_class_names_for(category).map { |name| "#{name}::Notification" }
  end

  def self.notifier_class_names_for(category)
    target = category.to_s
    descendants.select { |c| c.category_name == target }.map(&:name)
  end

  private

  # Plucking recipient_id without recipient_type rides on the check constraint
  # `recipient_type_user_only_v1`. A fork that drops it to notify a second
  # recipient type must pluck both columns and filter here.
  def email_permitted_recipient_ids
    @email_permitted_recipient_ids ||= User
      .where(id: notifications.pluck(:recipient_id))
      .includes(:preferences)
      .select { |user| deliver_email_now_for?(user) }
      .map(&:id)
      .to_set
  end

  def broadcast_notifications_arrival
    # Not `self.notifications`: the `inverse_of` link makes Bullet report a
    # false unused-eager-load in every spec that dispatches a notifier.
    recipient_ids = Noticed::Notification
                      .where(event_id: id, recipient_type: "User")
                      .pluck(:recipient_id)
    return if recipient_ids.empty?

    # Per-user iteration so one bad broadcast cannot poison the rest; each
    # call is self-rescuing.
    User.where(id: recipient_ids).find_each do |user|
      NotificationBroadcaster.refresh_for(user, announcement_key: "notifications.bell.arrival_announcement",
                                          severity: self.class.severity_name)
    end
  end

  # Reads `self.record`, not `params[:record]`: Noticed strips :record from
  # params before validation.
  # See /docs/developer/notifications (Idempotency).
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

    # A dispatch either side of a bucket boundary gets two keys and both
    # succeed. Intended: coalescing past the declared bucket is the digest's
    # job, not idempotency's.
    segments = [ self.class.name, seed_id ]
    segments.concat(Array(instance_exec(&self.class.dedup_seed_block))) if self.class.dedup_seed_block
    segments << instance_exec(&DEDUP_BUCKETS.fetch(self.class.dedup_bucket_granularity))
    self.idempotency_key = segments.join("_")
  end
end

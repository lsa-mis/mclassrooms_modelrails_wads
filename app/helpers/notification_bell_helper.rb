module NotificationBellHelper
  # The bell IS the indicator — no chip; severities tint via their saturated
  # signal tokens. `dark:text-danger-strong` on danger ONLY: the AAA-lightness
  # dark red reads as coral/pink at bell size; `-strong` restores its identity.
  # See /docs/developer/ui-patterns (Signals in graphics: the notification bell).
  SEVERITY_CLASSES = {
    danger:  { icon: "text-danger dark:text-danger-strong" },
    warning: { icon: "text-warning" },
    info:    { icon: "text-info"    },
    success: { icon: "text-success" }
  }.freeze

  # Indicator-dot bg colors, calibrated for WCAG 1.4.11 non-text 3:1 (the dot
  # is decorative; meaning is also in the aria-live region). `pulse: true` on
  # danger only, so reduced-motion users still get an instant indicator.
  # See /docs/developer/ui-patterns (Signals in graphics: the notification bell).
  SEVERITY_DOT_CLASSES = {
    danger:  { bg: "bg-danger-strong", pulse: true  },
    warning: { bg: "bg-warning",       pulse: false },
    info:    { bg: "bg-info",          pulse: false },
    success: { bg: "bg-success",       pulse: false }
  }.freeze

  def unread_notification_summary(user)
    UnreadNotificationSummary.new(user).to_h
  end

  def notification_bell_classes(severity, variant: :icon)
    table = variant == :dot ? SEVERITY_DOT_CLASSES : SEVERITY_CLASSES
    table.fetch(severity, table[:info])
  end

  # Normalizes any severity input to one of the four canonical values.
  # Used by the bell partial so `data-bell-severity` always reads as one
  # of [danger, warning, info, success], even if a notifier class slips
  # through with an off-canonical severity. Production paths are already
  # guarded by ApplicationNotifier's `severity` DSL validation, so this
  # is defensive coverage for test stubs, library injection, and other
  # non-production cases.
  def canonical_severity(severity)
    UnreadNotificationSummary::SEVERITY_RANK.key?(severity) ? severity : :info
  end

  def avatar_button_aria_label(user, summary = unread_notification_summary(user))
    if summary[:count].zero?
      t("navigation.user_menu_label", name: user.full_name)
    else
      t("navigation.user_menu_label_with_unread",
        name: user.full_name,
        count: summary[:count],
        phrase: t("notifications.severity_phrase.#{summary[:severity]}"))
    end
  end
end

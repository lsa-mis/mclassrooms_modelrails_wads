Rails.application.config.toasts = ActiveSupport::InheritableOptions.new(
  timing: {
    ms_per_word: 500,
    buffer_ms: 1000,
    min_ms: 5000,
    max_ms: 15000,
    stagger_ms: 2000
  },
  # Canonical severity ladder: info · success · warning · danger.
  # notice/alert/error are kept as Rails-flash aliases (flash[:notice]/[:alert]/[:error])
  # mapping to success/warning/danger styling, so existing flash calls keep working.
  types: {
    info: {
      tier: :pill,
      icon: :information_circle,
      # -on-toast, not -icon: the pill inverts and the page-ground icon token
      # does not follow it (#1236).
      icon_color: "text-info-icon-on-toast",
      progress: "bg-info-progress"
    },
    success: {
      tier: :pill,
      icon: :check_circle,
      icon_color: "text-success-icon-on-toast",
      progress: "bg-success-progress"
    },
    warning: {
      tier: :card,
      icon: :exclamation_triangle,
      # The tone's AAA text token, not -icon: -icon on the -surface fails 3:1 (#1236).
      icon_color: "text-warning",
      bg: "bg-warning-surface",
      border: "border-warning-border",
      text: "text-warning",
      close_hover: "hover:bg-warning-hover"
    },
    danger: {
      tier: :card,
      icon: :exclamation_circle,
      icon_color: "text-danger",
      bg: "bg-danger-surface",
      border: "border-danger-border",
      text: "text-danger",
      close_hover: "hover:bg-danger-hover"
    },
    # Rails-flash aliases (unchanged): notice→success, alert→warning, error→danger.
    notice: {
      tier: :pill,
      icon: :check_circle,
      icon_color: "text-success-icon-on-toast",
      progress: "bg-success-progress"
    },
    alert: {
      tier: :card,
      icon: :exclamation_triangle,
      icon_color: "text-warning",
      bg: "bg-warning-surface",
      border: "border-warning-border",
      text: "text-warning",
      close_hover: "hover:bg-warning-hover"
    },
    error: {
      tier: :card,
      icon: :exclamation_circle,
      icon_color: "text-danger",
      bg: "bg-danger-surface",
      border: "border-danger-border",
      text: "text-danger",
      close_hover: "hover:bg-danger-hover"
    }
  }
)

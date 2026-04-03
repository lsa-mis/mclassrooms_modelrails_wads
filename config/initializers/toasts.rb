Rails.application.config.toasts = ActiveSupport::InheritableOptions.new(
  timing: {
    ms_per_word: 500,
    buffer_ms: 1000,
    min_ms: 5000,
    max_ms: 15000,
    stagger_ms: 2000
  },
  types: {
    notice: {
      tier: :pill,
      icon: :check_circle,
      icon_color: "text-success-icon",
      progress: "bg-success-progress"
    },
    success: {
      tier: :pill,
      icon: :check_circle,
      icon_color: "text-success-icon",
      progress: "bg-success-progress"
    },
    info: {
      tier: :pill,
      icon: :information_circle,
      icon_color: "text-info-icon",
      progress: "bg-info-progress"
    },
    alert: {
      tier: :card,
      icon: :exclamation_triangle,
      icon_color: "text-warning-icon",
      bg: "bg-warning-surface",
      border: "border-warning-border",
      text: "text-warning",
      close_hover: "hover:bg-warning-hover"
    },
    error: {
      tier: :card,
      icon: :exclamation_circle,
      icon_color: "text-danger-icon",
      bg: "bg-danger-surface",
      border: "border-danger-border",
      text: "text-danger",
      close_hover: "hover:bg-danger-hover"
    }
  }
)

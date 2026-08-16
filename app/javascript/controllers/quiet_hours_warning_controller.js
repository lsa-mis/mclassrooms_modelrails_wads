import { Controller } from "@hotwired/stimulus"

// Deceptive-state warning: quiet hours `enabled` with ZERO day chips checked
// means quiet-hours-never-active (NotificationPreferences#quiet_hours_active?)
// while the toggle still reads "Enabled". Inputs are found by their stable
// `name` attributes (the JSONB key path).
// see /docs/developer/notifications
export default class extends Controller {
  static targets = ["warning"]

  connect() {
    this.boundCheck = this.check.bind(this)
    this.element.addEventListener("change", this.boundCheck)
    this.check()
  }

  disconnect() {
    this.element.removeEventListener("change", this.boundCheck)
  }

  check() {
    if (!this.hasWarningTarget) return

    const enabledInput = this.element.querySelector(
      'input[type="checkbox"][name="notification_preferences[quiet_hours][enabled]"]'
    )
    // Day chips render as type="checkbox" inside the sr-only span. The
    // hidden sentinel input shares the name but has type="hidden", so the
    // type filter excludes it cleanly.
    const dayInputs = this.element.querySelectorAll(
      'input[type="checkbox"][name="notification_preferences[quiet_hours][active_days][]"]'
    )

    const enabled = enabledInput?.checked === true
    const anyDayChecked = Array.from(dayInputs).some((cb) => cb.checked)

    if (enabled && !anyDayChecked) {
      this.warningTarget.classList.remove("hidden")
    } else {
      this.warningTarget.classList.add("hidden")
    }
  }
}

import { Controller } from "@hotwired/stimulus"

// Cycles through light → dark → system on click, updates the theme
// immediately, and persists the preference server-side for signed-in users.
export default class extends Controller {
  static values = {
    url: String,
    signedIn: { type: Boolean, default: false }
  }

  static targets = [ "lightIcon", "darkIcon", "systemIcon", "label" ]

  static CYCLE = [ "light", "dark", "system" ]

  connect() {
    this.updateVisuals()
  }

  cycle() {
    const current = this.currentTheme
    const index = this.constructor.CYCLE.indexOf(current)
    const next = this.constructor.CYCLE[(index + 1) % this.constructor.CYCLE.length]

    document.documentElement.dataset.themeThemeValue = next
    this.updateVisuals()

    if (this.signedInValue && this.urlValue) {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: `theme=${next}`
      })
    }
  }

  get currentTheme() {
    return document.documentElement.dataset.themeThemeValue || "system"
  }

  updateVisuals() {
    const theme = this.currentTheme
    const labels = { light: "Light", dark: "Dark", system: "System" }

    this.element.setAttribute("aria-label", labels[theme] || labels.system)

    if (this.hasLightIconTarget) this.lightIconTarget.classList.toggle("hidden", theme !== "light")
    if (this.hasDarkIconTarget) this.darkIconTarget.classList.toggle("hidden", theme !== "dark")
    if (this.hasSystemIconTarget) this.systemIconTarget.classList.toggle("hidden", theme !== "system")

    if (this.hasLabelTarget) {
      this.labelTarget.textContent = labels[theme] || labels.system
    }
  }
}

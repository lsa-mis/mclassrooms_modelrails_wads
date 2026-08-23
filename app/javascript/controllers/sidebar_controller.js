import { Controller } from "@hotwired/stimulus"

// Collapse state lives in three places, and all three have to move together:
// data-collapsed drives the CSS, aria-expanded is the only one assistive tech can see,
// and the cookie is the only one that survives navigation.
export default class extends Controller {
  static targets = [ "toggle" ]
  static values = { remember: { type: Boolean, default: true } }

  // A year, matching the theme preference. Lax so it rides same-site navigation.
  static COOKIE = "sidebar_collapsed"
  static MAX_AGE = 31536000

  toggle() {
    this.collapsed = !this.collapsed
  }

  open()  { this.collapsed = false }
  close() { this.collapsed = true  }

  get collapsed() {
    return this.element.dataset.collapsed === "true"
  }

  set collapsed(value) {
    this.element.dataset.collapsed = String(value)

    if (this.hasToggleTarget) {
      this.toggleTarget.setAttribute("aria-expanded", String(!value))
    }

    if (this.rememberValue) {
      document.cookie =
        `${this.constructor.COOKIE}=${value};path=/;max-age=${this.constructor.MAX_AGE};SameSite=Lax`
    }
  }
}

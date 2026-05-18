import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { delay: { type: Number, default: 300 } }

  search() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      this.element.requestSubmit()
    }, this.delayValue)
  }

  // Immediate submit (no debounce) — used by dropdown change events where
  // the user has made a deliberate single choice. Replaces inline
  // onchange="this.form.requestSubmit()" handlers that the CSP blocks.
  submit() {
    this.element.requestSubmit()
  }

  clear(event) {
    if (event.key === "Escape") {
      event.target.value = ""
      this.element.requestSubmit()
    }
  }
}

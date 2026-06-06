import { Controller } from "@hotwired/stimulus"

// Behavior for the floating-overlays band. Wave 5a wires popover (click toggle).
// Non-modal: CSS owns positioning; this owns open/close, aria-expanded sync,
// focus return, and Escape / outside-click dismissal. No focus trap (Tab may leave).
export default class extends Controller {
  static targets = ["trigger", "panel"]
  static values = { open: { type: Boolean, default: false } }

  connect() {
    if (this.openValue) this.open()
  }

  toggle() {
    this.openValue ? this.close() : this.open()
  }

  open() {
    if (this.openValue) return
    this.openValue = true
    this.panelTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.panelTarget.focus()
  }

  close() {
    if (!this.openValue) return
    this.openValue = false
    this.panelTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.triggerTarget.focus()
  }

  closeOnClickOutside(event) {
    if (this.openValue && !this.element.contains(event.target)) this.close()
  }
}

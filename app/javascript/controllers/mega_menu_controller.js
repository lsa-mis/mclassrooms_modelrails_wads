import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "panel", "chevron"]

  toggle() {
    const open = this.panelTarget.hidden
    this._setOpen(open)
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) this._setOpen(false)
  }

  _setOpen(open) {
    this.panelTarget.hidden = !open
    this.triggerTarget.setAttribute("aria-expanded", String(open))
    this.triggerTarget.dataset.state = open ? "open" : "closed"
    if (this.hasChevronTarget) {
      this.chevronTarget.dataset.state = open ? "open" : "closed"
    }
  }
}

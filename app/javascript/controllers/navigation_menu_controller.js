import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "content"]

  open() {
    clearTimeout(this._closeTimer)
    this._setOpen(true)
  }

  scheduleClose() {
    this._closeTimer = setTimeout(() => this._setOpen(false), 150)
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) this._setOpen(false)
  }

  _setOpen(open) {
    if (!this.hasContentTarget) return
    this.contentTarget.hidden = !open
    this.triggerTarget.setAttribute("aria-expanded", String(open))
    this.triggerTarget.dataset.state = open ? "open" : "closed"
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["fab", "panel", "icon"]

  toggle() {
    const open = this.panelTarget.hidden
    this._setOpen(open)
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) this._setOpen(false)
  }

  _setOpen(open) {
    this.panelTarget.hidden = !open
    this.fabTarget.setAttribute("aria-expanded", String(open))
    if (this.hasIconTarget) {
      this.iconTarget.style.transform = open ? "rotate(45deg)" : ""
    }
  }
}

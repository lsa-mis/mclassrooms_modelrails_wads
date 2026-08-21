import { Controller } from "@hotwired/stimulus"
import * as topLayer from "overlays/top_layer"

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
    // No-op unless the flyout is anchor-positioned (`position: fixed`); top_layer.js
    // refuses anything still on the pre-Baseline `absolute` fallback.
    if (open) {
      this.contentTarget.hidden = false
      topLayer.enable(this.contentTarget)
      topLayer.show(this.contentTarget)
    } else {
      topLayer.hide(this.contentTarget)
      topLayer.disable(this.contentTarget)
      this.contentTarget.hidden = true
    }
    this.triggerTarget.setAttribute("aria-expanded", String(open))
    this.triggerTarget.dataset.state = open ? "open" : "closed"
  }
}

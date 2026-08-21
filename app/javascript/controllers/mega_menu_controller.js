import { Controller } from "@hotwired/stimulus"
import * as topLayer from "overlays/top_layer"

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
    // No-op unless anchor-positioned (`position: fixed`); top_layer.js refuses the
    // pre-Baseline `absolute` fallback, where promotion would tear the panel off-screen.
    if (open) {
      this.panelTarget.hidden = false
      topLayer.enable(this.panelTarget)
      topLayer.show(this.panelTarget)
    } else {
      topLayer.hide(this.panelTarget)
      topLayer.disable(this.panelTarget)
      this.panelTarget.hidden = true
    }
    this.triggerTarget.setAttribute("aria-expanded", String(open))
    this.triggerTarget.dataset.state = open ? "open" : "closed"
    if (this.hasChevronTarget) {
      this.chevronTarget.dataset.state = open ? "open" : "closed"
    }
  }
}

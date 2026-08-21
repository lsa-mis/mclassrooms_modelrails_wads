import { Controller } from "@hotwired/stimulus"
import * as topLayer from "overlays/top_layer"

// Behavior for the floating-overlays band. Wave 5a wires popover (click toggle).
// Non-modal: CSS owns positioning; this owns open/close, aria-expanded sync,
// focus return, and Escape / outside-click dismissal. No focus trap (Tab may leave).
export default class extends Controller {
  static targets = ["trigger", "panel"]
  static values = {
    open: { type: Boolean, default: false },
    hideDelay: { type: Number, default: 150 }
  }

  connect() {
    if (this.openValue) this.open()
  }

  disconnect() {
    if (this.hideTimer) {
      clearTimeout(this.hideTimer)
      this.hideTimer = null
    }
  }

  toggle() {
    this.openValue ? this.close() : this.open()
  }

  open() {
    if (this.openValue) return
    this.openValue = true
    this.panelTarget.hidden = false
    // No-op unless the panel is anchor-positioned (`position: fixed`); top_layer.js
    // refuses anything still on the pre-Baseline `absolute` fallback. The CSS-shown
    // tooltip/hover_card paths below never reach here.
    topLayer.enable(this.panelTarget)
    topLayer.show(this.panelTarget)
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.panelTarget.focus()
  }

  close() {
    if (!this.openValue) return
    this.openValue = false
    topLayer.hide(this.panelTarget)
    topLayer.disable(this.panelTarget)
    this.panelTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.triggerTarget.focus()
  }

  closeOnClickOutside(event) {
    if (this.openValue && !this.element.contains(event.target)) this.close()
  }

  // Tooltip (CSS-shown) dismissal — the one thing CSS can't do: dismiss-while-hovered
  // (WCAG 1.4.13). Escape sets data-dismissed (CSS force-hides via group-data-[dismissed]);
  // mouseleave/focusout clear it so the next hover/focus shows it again.
  dismiss() {
    this.element.setAttribute("data-dismissed", "")
  }

  clearDismissed() {
    this.element.removeAttribute("data-dismissed")
  }

  // Hover-intent for hover_card (interactive content): open on enter/focus, close on
  // leave/blur AFTER a short delay so the pointer can cross the trigger→card gap (and
  // brief mouse-outs) without the card vanishing — what CSS :hover can't do. Escape
  // closes now and returns focus to the trigger.
  hoverOpen() {
    if (this.escaping) return
    if (this.hideTimer) {
      clearTimeout(this.hideTimer)
      this.hideTimer = null
    }
    this.element.dataset.state = "open"
  }

  hoverClose() {
    this.hideTimer = setTimeout(() => {
      this.element.dataset.state = "closed"
      this.hideTimer = null
    }, this.hideDelayValue)
  }

  hoverEscape() {
    if (this.hideTimer) {
      clearTimeout(this.hideTimer)
      this.hideTimer = null
    }
    this.element.dataset.state = "closed"
    if (this.hasPanelTarget) {
      const focusable = "a[href], button, input, select, textarea, [tabindex]:not([tabindex='-1'])"
      const trigger = Array.from(this.element.querySelectorAll(focusable))
        .find((el) => !this.panelTarget.contains(el))
      // Returning focus to the trigger fires focusin->hoverOpen synchronously; this
      // one-tick guard stops that from re-opening the card we just closed.
      this.escaping = true
      trigger?.focus()
      this.escaping = false
    }
  }
}

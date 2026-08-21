import { Controller } from "@hotwired/stimulus"
import * as topLayer from "overlays/top_layer"

export default class extends Controller {
  static targets = ["trigger", "popover", "label", "hidden"]

  connect() {
    this.#outsideHandler = (e) => {
      if (!this.element.contains(e.target)) this.close()
    }
  }

  disconnect() {
    document.removeEventListener("click", this.#outsideHandler)
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    // No-op unless the panel is anchor-positioned (`position: fixed`); top_layer.js
    // refuses anything still on the pre-Baseline `absolute` fallback.
    this.popoverTarget.dataset.open = "true"
    topLayer.enable(this.popoverTarget)
    topLayer.show(this.popoverTarget)
    this.triggerTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.#outsideHandler)
    this.isOpen = true
  }

  close() {
    topLayer.hide(this.popoverTarget)
    topLayer.disable(this.popoverTarget)
    this.popoverTarget.dataset.open = "false"
    this.triggerTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.#outsideHandler)
    this.isOpen = false
  }

  // Escape inside the popover (or any explicit dismissal) closes AND returns focus to
  // the trigger so keyboard users are never stranded in a hidden subtree (APG dialog).
  closeAndFocus(event) {
    if (event) event.preventDefault()
    this.close()
    this.triggerTarget.focus()
  }

  // Escape on the trigger while open closes the popover in place.
  triggerKeydown(event) {
    if (event.key === "Escape" && this.isOpen) {
      event.preventDefault()
      this.close()
    }
  }

  dateSelected(event) {
    const iso = event.detail.date
    const [year, month, day] = iso.split("-").map(Number)
    const d = new Date(year, month - 1, day)

    this.labelTarget.textContent = d.toLocaleDateString("default", {
      month: "long",
      day: "numeric",
      year: "numeric"
    })

    if (this.hasHiddenTarget) this.hiddenTarget.value = iso

    this.closeAndFocus()
  }

  #outsideHandler = null
  isOpen = false
}

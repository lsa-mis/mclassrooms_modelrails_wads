import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]
  static values = { open: { type: Boolean, default: false } }

  toggle() {
    this.openValue = !this.openValue
  }

  close() {
    this.openValue = false
  }

  openValueChanged() {
    this.menuTarget.classList.toggle("hidden", !this.openValue)
    this.element.querySelector("[aria-expanded]")
      ?.setAttribute("aria-expanded", this.openValue)
  }

  handleKeydown(event) {
    if (event.key === "Escape") this.close()
  }
}

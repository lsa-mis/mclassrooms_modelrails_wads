import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "method", "switch"]
  static values = { confirm: String }

  hold(event) {
    if (this.pending) event.preventDefault()
  }

  toggle() {
    const listing = this.switchTarget.checked

    if (!listing && !window.confirm(this.confirmValue)) {
      this.switchTarget.checked = true
      return
    }

    this.methodTarget.value = listing ? "delete" : "post"
    this.pending = true
    this.switchTarget.setAttribute("aria-disabled", "true")
    this.formTarget.requestSubmit()
  }

  settle(event) {
    this.pending = false
    this.switchTarget.removeAttribute("aria-disabled")
    if (!event.detail.success) this.switchTarget.checked = !this.switchTarget.checked
  }
}

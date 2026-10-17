import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "switch"]
  static values = { confirm: String }

  toggle() {
    if (!this.switchTarget.checked && !window.confirm(this.confirmValue)) {
      this.switchTarget.checked = true
      return
    }

    this.formTarget.requestSubmit()
  }
}

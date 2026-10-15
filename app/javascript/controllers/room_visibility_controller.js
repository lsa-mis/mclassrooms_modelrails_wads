import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["switch", "submit"]
  static values = { confirm: String }

  sync() {
    if (!this.hasSwitchTarget || !this.hasSubmitTarget) return

    if (this.switchTarget.defaultChecked && !this.switchTarget.checked) {
      this.submitTarget.dataset.turboConfirm = this.confirmValue
    } else {
      delete this.submitTarget.dataset.turboConfirm
    }
  }
}

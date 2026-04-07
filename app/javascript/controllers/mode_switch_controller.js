import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { mode: { type: String, default: "default" } }
  static targets = ["section"]

  modeValueChanged() {
    this.sectionTargets.forEach(section => {
      section.hidden = section.dataset.mode !== this.modeValue
    })
  }

  switchTo(event) {
    this.modeValue = event.params.mode
  }
}

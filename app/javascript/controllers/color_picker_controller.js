import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview"]
  static values = { color: { type: String, default: "oklch(0.55 0.18 233)" } }

  connect() {
    this.updatePreview()
  }

  update() {
    this.colorValue = this.inputTarget.value
    this.updatePreview()
  }

  updatePreview() {
    if (this.hasPreviewTarget) {
      this.previewTarget.style.setProperty("--ws-primary", this.colorValue)
    }
  }
}

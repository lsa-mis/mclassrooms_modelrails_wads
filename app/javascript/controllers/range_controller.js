import { Controller } from "@hotwired/stimulus"

// Mirrors the slider's current value into the associated <output> readout.
export default class extends Controller {
  static targets = ["input", "output"]

  connect() { this.#sync() }

  sync() { this.#sync() }

  #sync() {
    if (this.hasInputTarget && this.hasOutputTarget) {
      this.outputTarget.textContent = this.inputTarget.value
    }
  }
}

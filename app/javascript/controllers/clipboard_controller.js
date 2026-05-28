import { Controller } from "@hotwired/stimulus"

// Copy-to-clipboard. Used by the workspace settings join-policy section
// to make the shareable join link easy to grab.
//
// Markup:
//   data-controller="clipboard"
//   data-clipboard-target="source"  -> the input/textarea holding the value
//   data-clipboard-target="label"   -> button label that briefly toggles to "Copied!"
//   data-clipboard-target="status"  -> aria-live region for screen readers
//   data-action="clipboard#copy"    -> on the copy button
export default class extends Controller {
  static targets = ["source", "label", "status"]

  async copy() {
    const value = this.sourceTarget.value
    try {
      await navigator.clipboard.writeText(value)
      this.#flash("Copied!")
    } catch (_e) {
      // Fallback for older browsers / non-secure contexts
      this.sourceTarget.select()
      document.execCommand("copy")
      this.#flash("Copied!")
    }
  }

  #flash(message) {
    const originalLabel = this.labelTarget.textContent
    this.labelTarget.textContent = message
    if (this.hasStatusTarget) this.statusTarget.textContent = message

    setTimeout(() => {
      this.labelTarget.textContent = originalLabel
      if (this.hasStatusTarget) this.statusTarget.textContent = ""
    }, 1800)
  }
}

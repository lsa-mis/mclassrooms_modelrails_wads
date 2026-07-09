import { Controller } from "@hotwired/stimulus"

// Copy-to-clipboard for the room share line (Brief §5.3). Fork-owned:
// the template's clipboard_controller hardcodes an English label.
//   data-share-text-value            -> presenter.share_text
//   data-share-copied-message-value  -> t('rooms.show.share.copied')
//   data-share-target="status"       -> aria-live="polite" region
export default class extends Controller {
  static targets = ["status"]
  static values = { text: String, copiedMessage: String }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.textValue)
    } catch {
      const scratch = document.createElement("textarea")
      scratch.value = this.textValue
      this.element.appendChild(scratch)
      scratch.select()
      document.execCommand("copy")
      scratch.remove()
    }
    this.statusTarget.textContent = this.copiedMessageValue
    clearTimeout(this.resetTimer)
    this.resetTimer = setTimeout(() => { this.statusTarget.textContent = "" }, 3000)
  }

  disconnect() { clearTimeout(this.resetTimer) }
}

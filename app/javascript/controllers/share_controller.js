import { Controller } from "@hotwired/stimulus"

// Share the room. On devices that offer the OS share sheet (navigator.share —
// phones/tablets) we open it: the expected "send this to someone" affordance.
// Everywhere else (most desktops) we fall back to copy-to-clipboard. Fork-owned
// (the template's clipboard_controller hardcodes an English label).
//   data-share-text-value            -> presenter.share_text (clipboard payload)
//   data-share-url-value             -> canonical room URL (share-sheet link)
//   data-share-title-value           -> room display name (share-sheet title)
//   data-share-copied-message-value  -> t('rooms.show.share.copied')
//   data-share-native-label-value    -> t('rooms.show.share.native_button') ("Share")
//   data-share-target="status"       -> aria-live="polite" region
//   data-share-target="button"       -> the trigger, relabeled when native share is live
export default class extends Controller {
  static targets = ["status", "button"]
  static values = {
    text: String, url: String, title: String,
    copiedMessage: String, nativeLabel: String
  }

  connect() {
    // A copy-labelled button that opens a share sheet is a surprise; relabel it
    // to "Share" when (and only when) the native path will actually be taken.
    if (this.#nativeShareAvailable() && this.hasButtonTarget && this.hasNativeLabelValue) {
      this.buttonTarget.textContent = this.nativeLabelValue
    }
  }

  async copy() {
    if (this.#nativeShareAvailable()) {
      try {
        await navigator.share(this.#payload())
        return // the sheet IS the feedback — don't also announce "copied"
      } catch (error) {
        if (error?.name === "AbortError") return // user dismissed the sheet
        // any other failure falls through to the clipboard path
      }
    }
    await this.#copyToClipboard()
  }

  #nativeShareAvailable() {
    if (typeof navigator.share !== "function") return false
    if (typeof navigator.canShare !== "function") return true
    try { return navigator.canShare(this.#payload()) } catch { return false }
  }

  // Title + canonical URL make a clean sheet; the full share_text (which already
  // embeds the URL) is the clipboard payload, so the link isn't duplicated here.
  #payload() {
    const payload = {}
    if (this.hasTitleValue && this.titleValue) payload.title = this.titleValue
    if (this.hasUrlValue && this.urlValue) payload.url = this.urlValue
    if (!payload.title && !payload.url) payload.text = this.textValue // keep the call valid
    return payload
  }

  async #copyToClipboard() {
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

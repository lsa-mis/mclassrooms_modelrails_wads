import { Controller } from "@hotwired/stimulus"

// Swaps initials in when the avatar image fails to load. `fallback:` alone only covers a
// NIL src; a 404 still leaves the browser's broken-image glyph, and the `error` event is
// the only signal for it. CSP forbids an inline `onerror`, so it lives here.
export default class extends Controller {
  static targets = ["image", "fallback"]

  // The error can fire BEFORE this controller connects — a fast 404 beats module loading,
  // and a cached failure never fires at all. `complete && naturalWidth === 0` is the only
  // way to detect that after the fact, so the swap cannot depend on catching the event.
  connect() {
    // hasImageTarget: after a swap the <img> is gone, and re-connecting (a DOM move, a
    // Turbo restore) would otherwise throw on a missing target.
    if (!this.hasImageTarget) return

    const img = this.imageTarget
    if (img.complete && img.naturalWidth === 0) this.showFallback()
  }

  showFallback() {
    // The <img> carries the accessible name, so it is removed rather than hidden — a
    // hidden-but-present img would keep announcing a picture that never arrived.
    this.imageTarget.remove()
    this.fallbackTarget.hidden = false
  }
}

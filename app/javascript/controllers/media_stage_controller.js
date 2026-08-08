import { Controller } from "@hotwired/stimulus"

// Two-mode media stage: pano (default when present) <-> photos, toggled by a
// single chip. Photo browsing happens IN the frame; the popout stays in sync
// via the gallery controller's "gallery:navigated" event. The pano target
// carries data-turbo-permanent — it is only ever hidden, never removed, so a
// booted WebGL viewer survives mode switches (same rule the old tabs obeyed).
// Mode resets to the server-rendered default on a morph; the old tabs did too.
export default class extends Controller {
  static targets = ["pano", "photosLayer", "slide", "badge", "chipToPhotos", "chipToPano"]
  static values = { index: { type: Number, default: 0 }, badgeFormat: { type: String, default: "" } }

  // Both toggles hide the very button the user just activated to trigger
  // them (WCAG 2.4.3 / 2.1.1) — a keyboard user pressing Enter on the chip
  // otherwise loses focus to <body> when their button disappears. Only move
  // focus when that button actually held it, so a hypothetical
  // programmatic/mouse-without-focus call never steals focus from elsewhere.
  showPhotos() {
    const hadFocus = this.hasChipToPhotosTarget && document.activeElement === this.chipToPhotosTarget
    if (this.hasPanoTarget) this.panoTarget.hidden = true
    this.photosLayerTarget.hidden = false
    if (this.hasChipToPhotosTarget) this.chipToPhotosTarget.hidden = true
    if (this.hasChipToPanoTarget) {
      this.chipToPanoTarget.hidden = false
      if (hadFocus) this.chipToPanoTarget.focus()
    }
    this.render()
  }

  showPano() {
    const hadFocus = this.hasChipToPanoTarget && document.activeElement === this.chipToPanoTarget
    this.photosLayerTarget.hidden = true
    if (this.hasPanoTarget) this.panoTarget.hidden = false
    if (this.hasChipToPanoTarget) this.chipToPanoTarget.hidden = true
    if (this.hasChipToPhotosTarget) {
      this.chipToPhotosTarget.hidden = false
      if (hadFocus) this.chipToPhotosTarget.focus()
    }
  }

  prev() { this.step(-1) }
  next() { this.step(1) }

  step(delta) {
    if (this.dialogOpen) return  // popout owns the arrow keys while open
    const n = this.slideTargets.length
    this.indexValue = ((this.indexValue + delta) % n + n) % n
    this.render()
  }

  syncFromPopout({ detail: { index } }) {
    this.indexValue = index
    this.render()
  }

  render() {
    // Capture focus BEFORE hiding anything — setting `hidden` on the
    // currently-focused slide blurs it to <body> (WCAG 2.4.3 / 2.1.1), and a
    // keyboard user who tabbed to a slide then pressed an arrow key would
    // dead-end: the arrow-key listener lives on the frame container, and
    // <body> never bubbles it back. Only follow focus onto the incoming
    // slide when the outgoing one actually held it — a mouse click on the
    // prev/next chevrons (which never receive slide focus) must not steal
    // focus away from wherever the pointer interaction left it.
    const outgoing = this.slideTargets.find((el) => !el.hidden)
    const hadFocus = !!outgoing && document.activeElement === outgoing

    this.slideTargets.forEach((el, i) => { el.hidden = i !== this.indexValue })
    const current = this.slideTargets[this.indexValue]
    if (hadFocus && current) current.focus()
    if (!current || !this.hasBadgeTarget) return

    const caption = current.dataset.mediaStageCaption
    const position = current.dataset.mediaStagePosition
    // Single source of truth for the "caption · position" format: the
    // rooms.show.photo_badge YAML key, passed down via the badgeFormat value
    // (see _media_stage.html.erb's comment on how it's extracted intact).
    this.badgeTarget.textContent = caption
      ? this.badgeFormatValue.replace("%{caption}", caption).replace("%{position}", position)
      : position
  }

  get dialogOpen() {
    return !!this.element.querySelector("dialog[open]")
  }
}

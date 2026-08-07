import { Controller } from "@hotwired/stimulus"

// Two-mode media stage: pano (default when present) <-> photos, toggled by a
// single chip. Photo browsing happens IN the frame; the popout stays in sync
// via the gallery controller's "gallery:navigated" event. The pano target
// carries data-turbo-permanent — it is only ever hidden, never removed, so a
// booted WebGL viewer survives mode switches (same rule the old tabs obeyed).
// Mode resets to the server-rendered default on a morph; the old tabs did too.
export default class extends Controller {
  static targets = ["pano", "photosLayer", "slide", "badge", "chipToPhotos", "chipToPano"]
  static values = { index: { type: Number, default: 0 } }

  showPhotos() {
    if (this.hasPanoTarget) this.panoTarget.hidden = true
    this.photosLayerTarget.hidden = false
    if (this.hasChipToPhotosTarget) this.chipToPhotosTarget.hidden = true
    if (this.hasChipToPanoTarget) this.chipToPanoTarget.hidden = false
    this.render()
  }

  showPano() {
    this.photosLayerTarget.hidden = true
    if (this.hasPanoTarget) this.panoTarget.hidden = false
    if (this.hasChipToPanoTarget) this.chipToPanoTarget.hidden = true
    if (this.hasChipToPhotosTarget) this.chipToPhotosTarget.hidden = false
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
    this.slideTargets.forEach((el, i) => { el.hidden = i !== this.indexValue })
    const current = this.slideTargets[this.indexValue]
    if (!current || !this.hasBadgeTarget) return
    const caption = current.dataset.mediaStageCaption
    const position = current.dataset.mediaStagePosition
    this.badgeTarget.textContent = caption ? `${caption} · ${position}` : position
  }

  get dialogOpen() {
    return !!this.element.querySelector("dialog[open]")
  }
}

import { Controller } from "@hotwired/stimulus"

// Index-aware lightbox coordinator. Triggers are any [data-gallery-index-param]
// elements inside this controller's scope, in DOM order. On open/prev/next it
// swaps the shared dialog image's src/alt, updates caption + counter, and
// dispatches "gallery:navigated" {index} so a host (e.g. a media stage) can
// stay in sync. Focus-trap/escape/restore stay in the reused modal controller.
export default class extends Controller {
  static targets = ["image", "caption", "count"]

  open({ params: { index } }) {
    this.show(index ?? 0)
  }

  prev() { this.show(this.index - 1) }
  next() { this.show(this.index + 1) }

  show(index) {
    const items = this.items
    if (items.length === 0) return
    this.index = ((index % items.length) + items.length) % items.length
    const { gallerySrcParam: src, galleryAltParam: alt, galleryCaptionParam: caption } =
      items[this.index].dataset
    this.imageTarget.src = src
    this.imageTarget.alt = alt || ""
    if (this.hasCaptionTarget) this.captionTarget.textContent = caption || ""
    if (this.hasCountTarget) this.countTarget.textContent = `${this.index + 1} / ${items.length}`
    this.dispatch("navigated", { detail: { index: this.index } })
  }

  get items() {
    return [...this.element.querySelectorAll("[data-gallery-index-param]")]
  }
}

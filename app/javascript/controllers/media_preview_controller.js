import { Controller } from "@hotwired/stimulus"

const PREVIEWABLE = [ "image/png", "image/jpeg", "image/webp", "image/gif" ]

export default class extends Controller {
  static targets = [ "frame", "image" ]

  show({ target }) {
    if (target.type !== "file" || !this.hasImageTarget) return

    const [ file ] = target.files || []
    this.release()

    if (file && PREVIEWABLE.includes(file.type)) {
      this.objectUrl = URL.createObjectURL(file)
      this.imageTarget.src = this.objectUrl
    } else {
      this.imageTarget.src = this.imageTarget.dataset.savedSrc
    }
    if (this.hasFrameTarget) this.frameTarget.hidden = !!file && !this.objectUrl
  }

  disconnect() {
    this.release()
  }

  release() {
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
    this.objectUrl = null
  }
}

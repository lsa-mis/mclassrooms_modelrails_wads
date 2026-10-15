import { Controller } from "@hotwired/stimulus"

const PREVIEWABLE = [ "image/png", "image/jpeg", "image/webp", "image/gif" ]

export default class extends Controller {
  static targets = [ "image" ]

  show({ target }) {
    const [ file ] = target.files || []
    if (!file || !this.hasImageTarget || !PREVIEWABLE.includes(file.type)) return

    this.release()
    this.objectUrl = URL.createObjectURL(file)
    this.imageTarget.src = this.objectUrl
  }

  disconnect() {
    this.release()
  }

  release() {
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
    this.objectUrl = null
  }
}

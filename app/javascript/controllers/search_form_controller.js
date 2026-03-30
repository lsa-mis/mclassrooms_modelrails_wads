import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { delay: { type: Number, default: 300 } }

  search() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      this.element.requestSubmit()
    }, this.delayValue)
  }

  clear(event) {
    if (event.key === "Escape") {
      event.target.value = ""
      this.element.requestSubmit()
    }
  }
}

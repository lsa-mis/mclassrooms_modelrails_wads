import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  reset(event) {
    if (event.target === this.element && event.detail.success) this.element.reset()
  }
}

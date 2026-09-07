import { Controller } from "@hotwired/stimulus"

// Page-load flashes reach their live region as a mutation (#901): the
// server renders them into a <template> beside the empty container, and this
// moves them in once the page is live, so assistive tech announces them the
// way it announces a streamed toast. The carrier removes itself.
export default class extends Controller {
  static values = { container: String }

  connect() {
    const container = document.getElementById(this.containerValue)
    if (container) container.append(this.element.content)
    this.element.remove()
  }
}

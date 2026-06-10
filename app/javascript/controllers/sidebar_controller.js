import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggle() {
    const collapsed = this.element.dataset.collapsed === "true"
    this.element.dataset.collapsed = String(!collapsed)
  }

  open()  { this.element.dataset.collapsed = "false" }
  close() { this.element.dataset.collapsed = "true"  }
}

import { Controller } from "@hotwired/stimulus"

// Auto-submits the owning form on change — notification preferences save each input immediately, no Submit button.
export default class extends Controller {
  submit(event) {
    const form = event.target.closest("form") || this.element.closest("form")
    if (form) form.requestSubmit()
  }
}

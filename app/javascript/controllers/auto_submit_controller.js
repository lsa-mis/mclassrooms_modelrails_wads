import { Controller } from "@hotwired/stimulus"

// Auto-submits the owning form on change — notification preferences save each input immediately, no Submit button.
export default class extends Controller {
  submit(event) {
    const form = event.target.closest("form") || this.element.closest("form")
    if (form) form.requestSubmit()
  }

  // A row that must stay discoverable uses aria-disabled instead of native
  // disabled — native removes it from the tab order entirely (#745). This
  // guard makes the declared state real: block the activation before
  // `change` (and the auto-submit) can fire.
  guardDisabled(event) {
    if (event.target.getAttribute("aria-disabled") === "true") event.preventDefault()
  }
}

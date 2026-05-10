import { Controller } from "@hotwired/stimulus"

// Auto-submit a form on `change` events. Used by the notification-preferences
// surface so each toggle / select / time-input writes its value as soon as the
// user changes it — no Submit button. Accepts a `data-action="change->auto-submit#submit"`
// or attaches itself when the controller is on the form element.
//
// Connect: no work needed; the action declaration on the input fires `submit`
//          via the standard Stimulus `data-action` mechanism.
//
// `event.target.requestSubmit()` walks up to the closest form, which is the
// element that owns the controller, so the form's PATCH method + Turbo Stream
// content type negotiation are preserved.
export default class extends Controller {
  submit(event) {
    const form = event.target.closest("form") || this.element.closest("form")
    if (form) form.requestSubmit()
  }
}

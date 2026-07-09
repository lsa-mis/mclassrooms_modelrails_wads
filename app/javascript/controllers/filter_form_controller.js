import { Controller } from "@hotwired/stimulus"

// Debounced auto-submit for the Find a Room filter form (MiClassrooms Phase 3
// Task 5, Brief §5.2). Distinct from `search_form_controller` (used by the
// workspace members filter bar) and the template's `auto_submit_controller`
// (plain, no debounce): text inputs (building/room name) fire on every
// keystroke, so `submit()` debounces to avoid a request per character —
// selects/checkboxes are a single deliberate choice, so `submitNow()` fires
// immediately.
//
// `requestSubmit()` walks the standard HTMLFormElement submit path, so the
// form's GET method + `data-turbo-frame`/`data-turbo-action` targeting (set
// on the <form> itself) are preserved — this controller only decides WHEN to
// submit, never how.
export default class extends Controller {
  static values = { delay: { type: Number, default: 300 } }

  submit() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }

  submitNow() {
    clearTimeout(this.timeout)
    this.element.requestSubmit()
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}

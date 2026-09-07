import { Controller } from "@hotwired/stimulus"

// Auto-submits the owning form on change — notification preferences save each input immediately, no Submit button.
//
// `debounce` (ms, default 0) lets a control that fires `change` per keystroke
// settle first: arrowing through a native <select> fires a change per option
// in some browser and reader pairs, and without this every intermediate
// value was written (#940). A pending submit is flushed when focus leaves the
// control, so leaving saves at once.
export default class extends Controller {
  static values = { debounce: { type: Number, default: 0 } }

  submit(event) {
    const form = event.target.closest("form") || this.element.closest("form")
    if (!form) return

    if (this.debounceValue > 0) {
      clearTimeout(this.timer)
      this.timer = setTimeout(() => { this.timer = null; form.requestSubmit() }, this.debounceValue)
    } else {
      form.requestSubmit()
    }
  }

  flush(event) {
    if (!this.timer) return
    clearTimeout(this.timer)
    this.timer = null
    const form = event.target.closest("form") || this.element.closest("form")
    if (form) form.requestSubmit()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  // A row that must stay discoverable uses aria-disabled instead of native
  // disabled — native removes it from the tab order entirely (#745). This
  // guard makes the declared state real: block the activation before
  // `change` (and the auto-submit) can fire.
  guardDisabled(event) {
    if (event.target.getAttribute("aria-disabled") === "true") event.preventDefault()
  }
}

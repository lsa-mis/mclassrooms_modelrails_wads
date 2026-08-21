import { Controller } from "@hotwired/stimulus"

// `indeterminate` is a DOM property with no HTML attribute, so a server-rendered
// checkbox cannot express it — it has to be set after the element exists. Everything
// else about the tri-state (the `:indeterminate` styling, the AT announcement) rides on
// that property, so this is the whole controller.
//
// Without JS the box renders unchecked, which is the honest degradation: a tri-state
// parent whose children are partly selected reads as "not all selected".
export default class extends Controller {
  connect() {
    this.element.indeterminate = true
  }

  // Once the user acts on it the box is no longer partial — let the native toggle stand.
  clear() {
    this.element.indeterminate = false
  }
}

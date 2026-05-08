import { Controller } from "@hotwired/stimulus"

// Toggles the mobile docs sidebar with a smooth max-height transition.
// The markdowndocs gem ships an inline-onclick handler for this; our strict
// CSP (script-src :self with nonces, no unsafe-inline) blocks inline
// handlers, so the host override of show.html.erb wires Stimulus instead.
export default class extends Controller {
  static targets = ["sidebar", "iconOpen", "iconClose"]

  toggle(event) {
    const button = event.currentTarget
    const isOpen = button.getAttribute("aria-expanded") === "true"
    button.setAttribute("aria-expanded", String(!isOpen))
    this.iconOpenTarget.classList.toggle("hidden", !isOpen)
    this.iconCloseTarget.classList.toggle("hidden", isOpen)

    if (isOpen) {
      this.sidebarTarget.style.maxHeight = "0px"
    } else {
      this.sidebarTarget.style.maxHeight = `${this.sidebarTarget.scrollHeight}px`
    }
  }
}

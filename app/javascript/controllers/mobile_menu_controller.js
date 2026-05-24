import { Controller } from "@hotwired/stimulus"

// Mobile-accordion header panel. Open/close/closeOnLinkClick with focus
// management so keyboard and screen-reader users have a coherent flow:
// - On open: move focus into the first focusable element in the panel
//   so AT gets a narrative entry into the revealed content.
// - On explicit close (Escape): return focus to the toggle.
// - On auto-close after a link click: ALSO return focus to the toggle so
//   focus doesn't fall to <body> mid-Turbo-visit. Turbo Drive may resolve
//   the navigation and reset focus to its natural starting point; that's
//   the right hand-off.
// Escape is wired at the header element via `keydown@window->mobile-menu#close`
// so it works regardless of which descendant has focus.
export default class extends Controller {
  static targets = ["menu", "button", "label"]
  static values = { openLabel: String, closeLabel: String }

  toggle() {
    if (this.menuTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.menuTarget.classList.remove("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.#setLabel(this.closeLabelValue)
    // requestAnimationFrame so the panel is actually painted before we
    // attempt to move focus — focus() on a still-hidden element is a no-op.
    requestAnimationFrame(() => {
      const first = this.menuTarget.querySelector(
        'a, button, input, select, textarea, [tabindex]:not([tabindex="-1"])'
      )
      if (first) first.focus()
    })
  }

  // Close on Escape (wired via keydown@window) or any explicit dismissal.
  close(event) {
    // Escape-key path: only act when the panel is open.
    if (event && event.type === "keydown") {
      if (event.key !== "Escape") return
      if (this.menuTarget.classList.contains("hidden")) return
    }
    this.menuTarget.classList.add("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.#setLabel(this.openLabelValue)
    this.buttonTarget.focus()
  }

  // Auto-dismiss the expanded panel when any anchor inside it is activated.
  // Wired at the header partial on the menu element; the action delegates via
  // event bubbling, so no per-link wiring is required. Restoring focus to the
  // toggle gives AT a known location during the Turbo Drive transition.
  closeOnLinkClick(event) {
    if (event.target.closest("a") && !this.menuTarget.classList.contains("hidden")) {
      this.menuTarget.classList.add("hidden")
      this.buttonTarget.setAttribute("aria-expanded", "false")
      this.#setLabel(this.openLabelValue)
      this.buttonTarget.focus()
    }
  }

  // Click-outside-to-dismiss. Wired at the controller's root element
  // (the <header>) via `click@window->mobile-menu#closeOnOutsideClick`,
  // so every click in the document bubbles up to this handler. We
  // short-circuit when the panel is already closed OR when the click
  // originated inside the header — covers the hamburger, theme toggle,
  // avatar trigger, and anything else in chrome.
  // Unlike close(), we do NOT refocus the hamburger button: the user is
  // interacting with something elsewhere on the page; stealing focus
  // back to the toggle would be jarring and would steal their click's
  // intended target focus.
  closeOnOutsideClick(event) {
    if (this.menuTarget.classList.contains("hidden")) return
    if (this.element.contains(event.target)) return
    this.menuTarget.classList.add("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.#setLabel(this.openLabelValue)
  }

  #setLabel(text) {
    if (this.hasLabelTarget && text) this.labelTarget.textContent = text
  }
}

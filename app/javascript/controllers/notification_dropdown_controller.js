import { Controller } from "@hotwired/stimulus"

// Notifications bell dropdown — opens a panel scoped under the bell trigger.
//
// Targets:
//   trigger — the bell <button>
//   panel   — the dropdown <div> (initially `hidden`)
//
// Methods:
//   toggle()  — flip open ↔ closed
//   open()    — show panel, set aria-expanded="true", attach outside-click + keydown listeners
//   close()   — hide panel, set aria-expanded="false", return focus to trigger
//
// Distinct from `dropdown_controller.js` (the user menu) so the two surfaces
// don't share state. Keyboard shortcut + arrow-key navigation arrive in a
// follow-up cycle.
export default class extends Controller {
  static targets = ["trigger", "panel"]

  connect() {
    this.handleOutsideClick = this.handleOutsideClick.bind(this)
    this.handleKeydown = this.handleKeydown.bind(this)
    this.handleGlobalShortcut = this.handleGlobalShortcut.bind(this)

    // Global toggle is bound on connect so it works from anywhere on the
    // page; outside-click + scoped keydown only attach while open.
    document.addEventListener("keydown", this.handleGlobalShortcut)
  }

  disconnect() {
    document.removeEventListener("click", this.handleOutsideClick, true)
    document.removeEventListener("keydown", this.handleKeydown)
    document.removeEventListener("keydown", this.handleGlobalShortcut)
  }

  toggle() {
    if (this.isOpen()) {
      this.close()
    } else {
      this.open()
    }
  }

  open() {
    this.panelTarget.classList.remove("hidden")
    this.triggerTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.handleOutsideClick, true)
    document.addEventListener("keydown", this.handleKeydown)
  }

  close() {
    this.panelTarget.classList.add("hidden")
    this.triggerTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.handleOutsideClick, true)
    document.removeEventListener("keydown", this.handleKeydown)
    this.triggerTarget.focus()
  }

  isOpen() {
    return !this.panelTarget.classList.contains("hidden")
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    }
  }

  // Global Cmd/Ctrl + Shift + N toggle. Lowercase comparison covers cases
  // where Shift modifies the key (some browsers report "N" instead of "n").
  handleGlobalShortcut(event) {
    const isShortcut =
      (event.metaKey || event.ctrlKey) &&
      event.shiftKey &&
      event.key.toLowerCase() === "n"

    if (!isShortcut) return

    event.preventDefault()
    this.toggle()
  }
}

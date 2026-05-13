import { Controller } from "@hotwired/stimulus"

// Notifications bell dropdown — opens a panel scoped under the bell trigger.
//
// Targets:
//   trigger — the bell <button>
//   panel   — the dropdown <div> (initially `hidden`)
//
// Methods:
//   toggle()  — flip open ↔ closed
//   open()    — show panel, set aria-expanded="true", focus the first
//               notification item (if any), attach outside-click +
//               keydown listeners
//   close()   — hide panel, set aria-expanded="false", return focus to trigger
//
// Keyboard behavior while open:
//   Escape    — close
//   ArrowDown — focus next item (wraps at end)
//   ArrowUp   — focus previous item (wraps at start)
//   Home      — focus first item
//   End       — focus last item
//
// Global keyboard shortcut (always on, regardless of open state):
//   Cmd/Ctrl + Shift + N — toggle the dropdown
//
// Distinct from `dropdown_controller.js` (the user menu) so the two surfaces
// don't share state.
export default class extends Controller {
  static targets = ["trigger", "panel"]

  connect() {
    this.handleOutsideClick = this.handleOutsideClick.bind(this)
    this.handleKeydown = this.handleKeydown.bind(this)
    this.handleGlobalShortcut = this.handleGlobalShortcut.bind(this)
    this.handleStreamRender = this.handleStreamRender.bind(this)

    // Global toggle is bound on connect so it works from anywhere on the
    // page; outside-click + scoped keydown only attach while open.
    document.addEventListener("keydown", this.handleGlobalShortcut)
    // Focus restoration: when a broadcast replaces the dropdown list
    // frame mid-keyboard-navigation, the active element gets nuked and
    // focus falls back to <body>. We capture the focused item's id
    // pre-render and reapply post-render so SR/keyboard users don't
    // lose their place across cross-tab read-state changes or new
    // notification arrivals.
    document.addEventListener("turbo:before-stream-render", this.handleStreamRender)
  }

  disconnect() {
    document.removeEventListener("click", this.handleOutsideClick, true)
    document.removeEventListener("keydown", this.handleKeydown)
    document.removeEventListener("keydown", this.handleGlobalShortcut)
    document.removeEventListener("turbo:before-stream-render", this.handleStreamRender)
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

    // Move focus to the first item so keyboard users can start navigating
    // immediately. No-op when the dropdown is empty (no items rendered).
    const first = this.items()[0]
    if (first) first.focus()
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
    switch (event.key) {
      case "Escape":
        event.preventDefault()
        this.close()
        return
      case "ArrowDown":
        event.preventDefault()
        this.focusItem(this.currentIndex() + 1)
        return
      case "ArrowUp":
        event.preventDefault()
        this.focusItem(this.currentIndex() - 1)
        return
      case "Home":
        event.preventDefault()
        this.focusItem(0)
        return
      case "End":
        event.preventDefault()
        this.focusItem(this.items().length - 1)
        return
    }
  }

  // Returns the cyclable focus targets: the anchor inside each notification
  // item. Header chrome (heading, "see all" link) is reachable via Tab — only
  // the list items participate in arrow-key cycling.
  items() {
    return Array.from(
      this.panelTarget.querySelectorAll("[data-notification-item] a")
    )
  }

  currentIndex() {
    return this.items().indexOf(document.activeElement)
  }

  // Wraps index into [0, length). focusItem(-1) on a 3-item list focuses
  // index 2; focusItem(3) focuses index 0. No-op when the list is empty.
  focusItem(index) {
    const list = this.items()
    if (list.length === 0) return
    const wrapped = ((index % list.length) + list.length) % list.length
    list[wrapped].focus()
  }

  // Capture focus pre-render and restore it post-render when a Turbo
  // Stream replaces the dropdown-list frame. Notification items have
  // stable `dom_id(notification, :dropdown)` ids on the wrapping <li>,
  // so we look up the same id in the freshly-rendered DOM and focus
  // its <a> child. If the previously-focused item is gone (e.g., it
  // was removed in the broadcast — currently not a case in this app
  // but defensive), focus falls back to whatever the post-render
  // active element is.
  handleStreamRender(event) {
    const streamEl = event.target
    if (streamEl.getAttribute("target") !== "notifications_dropdown_frame") return

    const focused = document.activeElement
    const focusedItem = focused?.closest("[data-notification-item]")
    if (!focusedItem) return

    const focusedItemId = focusedItem.id
    const originalRender = event.detail.render

    event.detail.render = async (targetElement) => {
      await originalRender(targetElement)
      const restored = document.getElementById(focusedItemId)
      const link = restored?.querySelector("a")
      link?.focus()
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

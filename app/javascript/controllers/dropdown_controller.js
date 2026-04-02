import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "button"]

  connect() {
    this.close = this.close.bind(this)
    this.handleOutsideClick = this.handleOutsideClick.bind(this)
    this.handleKeydown = this.handleKeydown.bind(this)
  }

  disconnect() {
    document.removeEventListener("click", this.handleOutsideClick, true)
    document.removeEventListener("keydown", this.handleKeydown)
  }

  toggle() {
    if (this.isOpen()) {
      this.closeMenu()
    } else {
      this.openMenu()
    }
  }

  openMenu() {
    this.menuTarget.classList.remove("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.handleOutsideClick, true)
    document.addEventListener("keydown", this.handleKeydown)

    const firstItem = this.menuItems()[0]
    if (firstItem) firstItem.focus()
  }

  closeMenu() {
    this.menuTarget.classList.add("hidden")
    this.buttonTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.handleOutsideClick, true)
    document.removeEventListener("keydown", this.handleKeydown)
    this.buttonTarget.focus()
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.closeMenu()
    }
  }

  handleKeydown(event) {
    switch (event.key) {
      case "Escape":
        event.preventDefault()
        this.closeMenu()
        break
      case "ArrowDown":
        event.preventDefault()
        this.focusNextItem()
        break
      case "ArrowUp":
        event.preventDefault()
        this.focusPreviousItem()
        break
      case "Home":
        event.preventDefault()
        this.focusFirstItem()
        break
      case "End":
        event.preventDefault()
        this.focusLastItem()
        break
      case "Tab":
        this.closeMenu()
        break
    }
  }

  // Private

  isOpen() {
    return !this.menuTarget.classList.contains("hidden")
  }

  menuItems() {
    return [...this.menuTarget.querySelectorAll('[role="menuitem"]')]
  }

  focusNextItem() {
    const items = this.menuItems()
    const index = items.indexOf(document.activeElement)
    const next = items[index + 1] || items[0]
    next?.focus()
  }

  focusPreviousItem() {
    const items = this.menuItems()
    const index = items.indexOf(document.activeElement)
    const prev = items[index - 1] || items[items.length - 1]
    prev?.focus()
  }

  focusFirstItem() {
    this.menuItems()[0]?.focus()
  }

  focusLastItem() {
    const items = this.menuItems()
    items[items.length - 1]?.focus()
  }
}

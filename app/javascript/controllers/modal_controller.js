import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "panel"]
  static values = { open: { type: Boolean, default: false } }

  connect() {
    this.prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.handleCancel = this.handleCancel.bind(this)
    this.handleClick = this.handleClick.bind(this)
    this.closeTimer = null

    this.dialogTarget.addEventListener("cancel", this.handleCancel)
    this.dialogTarget.addEventListener("click", this.handleClick)

    if (this.openValue) {
      this.open()
    }
  }

  disconnect() {
    this.dialogTarget.removeEventListener("cancel", this.handleCancel)
    this.dialogTarget.removeEventListener("click", this.handleClick)

    if (this.closeTimer) {
      clearTimeout(this.closeTimer)
      this.closeTimer = null
    }

    if (this.dialogTarget.open) {
      this.dialogTarget.close()
    }
  }

  open() {
    if (this.dialogTarget.open) return

    const openDialogs = document.querySelectorAll("dialog[open]")
    if (openDialogs.length > 0) {
      console.warn("Modal: another dialog is already open. Stacked modals are not supported.")
    }

    this.previouslyFocused = document.activeElement
    this.dialogTarget.showModal()
    this.animateIn()
  }

  close() {
    this.animateOut(() => {
      if (this.dialogTarget.open) {
        this.dialogTarget.close()
      }
      this.previouslyFocused?.focus()
      this.previouslyFocused = null
    })
  }

  handleEscOnPage() {
    // When ESC is pressed on a page with a modal controller but the dialog
    // is NOT open, navigate back. When the dialog IS open, the native
    // <dialog> cancel event handles it (see handleCancel).
    if (!this.dialogTarget.open) {
      window.history.back()
    }
  }

  // Private

  handleCancel(event) {
    event.preventDefault()
    try {
      this.close()
    } catch {
      this.dialogTarget.close()
    }
  }

  handleClick(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }

  animateIn() {
    if (this.prefersReducedMotion) {
      this.panelTarget.style.opacity = "1"
      this.panelTarget.style.transform = "scale(1)"
      return
    }

    this.panelTarget.style.opacity = "0"
    this.panelTarget.style.transform = "scale(0.95)"
    requestAnimationFrame(() => {
      const duration = getComputedStyle(document.documentElement)
        .getPropertyValue("--modal-animation-duration").trim() || "200ms"
      this.panelTarget.style.transition = `opacity ${duration} ease-out, transform ${duration} ease-out`
      this.panelTarget.style.opacity = "1"
      this.panelTarget.style.transform = "scale(1)"
    })
  }

  animateOut(callback) {
    if (this.prefersReducedMotion) {
      this.panelTarget.style.opacity = "0"
      callback()
      return
    }

    const duration = getComputedStyle(document.documentElement)
      .getPropertyValue("--modal-animation-duration").trim() || "200ms"
    this.panelTarget.style.transition = `opacity ${duration} ease-in, transform ${duration} ease-in`
    this.panelTarget.style.opacity = "0"
    this.panelTarget.style.transform = "scale(0.95)"

    const ms = parseInt(duration, 10) || 200
    this.closeTimer = setTimeout(() => {
      this.closeTimer = null
      callback()
    }, ms)
  }
}

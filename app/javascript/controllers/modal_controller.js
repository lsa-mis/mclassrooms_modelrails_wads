import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "panel"]
  static values = {
    open: { type: Boolean, default: false },
    enterTransform: { type: String, default: "scale(1)" },
    leaveTransform: { type: String, default: "scale(0.95)" }
  }

  connect() {
    // Neutralize the panel's class-supplied `scale-95` on EVERY path — TW4
    // compiles it to the separate scale: property, which composes with the
    // inline transform below instead of being overridden; paths that skip
    // animateIn (server-rendered open dialogs) otherwise rest 5% shrunken
    // (a11y gate, 2026-07-13).
    if (this.hasPanelTarget) this.panelTarget.style.scale = "1"

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
    // Tailwind 4 regression (a11y gate, 2026-07-13): the panel's `scale-95`
    // class compiles to the separate `scale:` property, which COMPOSES with
    // the inline `transform: scale(1)` set below instead of being overridden
    // by it — every open panel rested at 95% (44px close buttons measured
    // 41.8px). Neutralize the class's channel; the inline transform owns the
    // animation from here.
    this.panelTarget.style.scale = "1"

    if (this.prefersReducedMotion) {
      this.panelTarget.style.opacity = "1"
      this.panelTarget.style.transform = this.enterTransformValue
      document.dispatchEvent(new CustomEvent("modal:opened"))
      return
    }

    this.panelTarget.style.opacity = "0"
    this.panelTarget.style.transform = this.leaveTransformValue
    requestAnimationFrame(() => {
      const duration = getComputedStyle(document.documentElement)
        .getPropertyValue("--modal-animation-duration").trim() || "200ms"
      this.panelTarget.style.transition = `opacity ${duration} ease-out, transform ${duration} ease-out`
      this.panelTarget.style.opacity = "1"
      this.panelTarget.style.transform = this.enterTransformValue

      const ms = parseInt(duration, 10) || 200
      setTimeout(() => {
        document.dispatchEvent(new CustomEvent("modal:opened"))
      }, ms)
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
    this.panelTarget.style.transform = this.leaveTransformValue

    const ms = parseInt(duration, 10) || 200
    this.closeTimer = setTimeout(() => {
      this.closeTimer = null
      callback()
    }, ms)
  }
}

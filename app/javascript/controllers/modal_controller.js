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
    this.closeInsteadOfMorph = this.closeInsteadOfMorph.bind(this)
    this.closeTimer = null

    this.dialogTarget.addEventListener("cancel", this.handleCancel)
    this.dialogTarget.addEventListener("click", this.handleClick)
    this.element.addEventListener("turbo:before-morph-attribute", this.closeInsteadOfMorph)

    if (this.openValue) {
      this.open()
      this.previouslyFocused = null
    }
  }

  disconnect() {
    this.dialogTarget.removeEventListener("cancel", this.handleCancel)
    this.dialogTarget.removeEventListener("click", this.handleClick)
    this.element.removeEventListener("turbo:before-morph-attribute", this.closeInsteadOfMorph)

    if (this.closeTimer) {
      clearTimeout(this.closeTimer)
      this.closeTimer = null
    }

    if (this.dialogTarget.open) {
      // A dialog torn out of the DOM while open (Turbo replaced the page or a
      // stream removed the row) closes with NO native focus restore — restore
      // explicitly or focus silently lands on <body>.
      this.dialogTarget.close()
      this.restoreFocus()
    }
  }

  // Stacking is supported and needs no help: a second showModal() puts that dialog above
  // this one in the top layer, moves the focus trap, and gives it Escape. This used to
  // warn that stacked modals were unsupported and then stack them anyway.
  open() {
    if (this.dialogTarget.open) return

    this.previouslyFocused = document.activeElement
    this.dialogTarget.showModal()
    this.animateIn()
  }

  close() {
    this.animateOut(() => {
      if (this.dialogTarget.open) {
        this.dialogTarget.close()
      }
      this.restoreFocus()
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

  restoreFocus() {
    const target = [ this.previouslyFocused, this.visibleTrigger() ].find((el) => this.isFocusable(el)) ??
      document.querySelector('main[tabindex="-1"]')
    target?.focus()
    this.previouslyFocused = null
  }

  visibleTrigger() {
    const focusable = "button, a[href], [tabindex]"
    return [ ...this.element.querySelectorAll('[data-action~="click->modal#open"], [data-action~="modal#open"]') ]
      .map((trigger) => (trigger.matches(focusable) ? trigger : trigger.querySelector(focusable)))
      .find((el) => this.isFocusable(el))
  }

  isFocusable(el) {
    return !!el && el !== document.body && el.isConnected && !el.hidden && el.checkVisibility()
  }

  handleCancel(event) {
    event.preventDefault()
    try {
      this.close()
    } catch {
      this.dialogTarget.close()
    }
  }

  closeInsteadOfMorph(event) {
    if (!this.dialogTarget.open) return

    const { attributeName } = event.detail
    if (event.target === this.dialogTarget && attributeName === "open") {
      event.preventDefault()
      this.close()
    } else if (event.target === this.panelTarget && attributeName === "style") {
      event.preventDefault()
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

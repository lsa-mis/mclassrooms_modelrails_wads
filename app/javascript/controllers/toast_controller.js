import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { timeout: { type: Number, default: 0 } }
  static targets = [ "progress" ]

  connect() {
    this.prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.animateIn()

    if (this.timeoutValue > 0) {
      this.remaining = this.timeoutValue
      this.startAutoClose()
      this.startProgressBar()
    }
  }

  disconnect() {
    clearTimeout(this.dismissTimer)
  }

  dismiss() {
    this.element.style.pointerEvents = "none"
    const duration = this.prefersReducedMotion ? 0 : 300

    this.element.style.transition = `opacity ${duration}ms ease-in, transform ${duration}ms ease-in`
    this.element.style.opacity = "0"
    if (!this.prefersReducedMotion) {
      this.element.style.transform = "translateX(100%)"
    }

    setTimeout(() => this.element.remove(), duration)
  }

  pause() {
    if (this.timeoutValue === 0) return
    clearTimeout(this.dismissTimer)
    this.pausedAt = Date.now()

    if (this.hasProgressTarget) {
      this.progressTarget.style.transition = "none"
    }
  }

  resume() {
    if (this.timeoutValue === 0 || !this.pausedAt) return
    this.remaining -= (Date.now() - this.pausedAt)
    this.pausedAt = null

    if (this.remaining > 0) {
      this.startAutoClose()
      if (this.hasProgressTarget) {
        this.progressTarget.style.transition = `width ${this.remaining}ms linear`
        this.progressTarget.style.width = "0%"
      }
    } else {
      this.dismiss()
    }
  }

  // Private

  animateIn() {
    if (this.prefersReducedMotion) {
      this.element.style.opacity = "1"
      return
    }

    this.element.style.opacity = "0"
    this.element.style.transform = "translateX(100%)"
    requestAnimationFrame(() => {
      this.element.style.transition = "opacity 300ms ease-out, transform 300ms ease-out"
      this.element.style.opacity = "1"
      this.element.style.transform = "translateX(0)"
    })
  }

  startAutoClose() {
    this.dismissTimer = setTimeout(() => this.dismiss(), this.remaining)
  }

  startProgressBar() {
    if (!this.hasProgressTarget) return
    this.progressTarget.style.width = "100%"
    requestAnimationFrame(() => {
      this.progressTarget.style.transition = `width ${this.timeoutValue}ms linear`
      this.progressTarget.style.width = "0%"
    })
  }
}

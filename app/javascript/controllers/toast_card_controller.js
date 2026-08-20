import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.animateIn()
  }

  dismiss() {
    this.element.style.pointerEvents = "none"
    const duration = this.prefersReducedMotion ? 0 : 300

    this.element.style.transition = `opacity ${duration}ms ease-in`
    this.element.style.opacity = "0"

    setTimeout(() => this.element.remove(), duration)
  }

  animateIn() {
    if (this.prefersReducedMotion) {
      this.element.style.opacity = "1"
      return
    }

    this.element.style.opacity = "0"
    this.element.style.transform = "translateY(8px)"
    requestAnimationFrame(() => {
      this.element.style.transition = "opacity 300ms ease-out, transform 300ms ease-out"
      this.element.style.opacity = "1"
      this.element.style.transform = "translateY(0)"
    })
  }
}

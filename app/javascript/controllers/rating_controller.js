import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { value: Number, url: String }
  static targets = ["star", "input"]

  preview({ params: { index } }) {
    this.#render(index)
  }

  resetPreview() {
    this.#render(this.valueValue)
  }

  select({ params: { index } }) {
    this.valueValue = index
    if (this.hasInputTarget) this.inputTarget.value = index
    if (this.urlValue) this.#submit(index)
  }

  #render(upTo) {
    this.starTargets.forEach((star, i) => {
      const filled = i < upTo
      // Semantic warning-icon token — mirrors the server-rendered filled-star
      // class (was raw text-yellow-400). Keeps hover/select in sync with the AAA
      // graphic-contrast token instead of reintroducing the raw color in JS.
      star.classList.toggle("text-warning-icon", filled)
      star.classList.toggle("text-text-muted", !filled)
      const svg = star.querySelector("svg")
      if (svg) svg.setAttribute("fill", filled ? "currentColor" : "none")
    })
  }

  async #submit(value) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    try {
      await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          ...(token && { "X-CSRF-Token": token })
        },
        body: JSON.stringify({ value })
      })
    } catch {
      // network errors are silently ignored — host app handles them
    }
  }
}

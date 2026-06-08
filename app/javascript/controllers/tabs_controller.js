import { Controller } from "@hotwired/stimulus"

// WAI-ARIA APG tabs — AUTOMATIC activation. Roving tabindex across the role=tab buttons; the
// active tab is tabindex=0, the rest -1. ←/→ move focus AND activate (show the panel),
// wrapping and skipping aria-disabled tabs; Home/End jump to the first/last enabled tab; a
// click activates. Horizontal orientation only (no ArrowUp/Down). Panels render inline/eager,
// so activating on focus has no latency. INVARIANT: keep automatic — Enter/Space are no-ops
// because focus already activated.
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { index: Number }

  connect() {
    const start = this.#disabled(this.indexValue) ? (this.#firstEnabled() ?? 0) : this.indexValue
    this.#activate(start, { focus: false })
  }

  // click on a tab
  select(event) {
    const i = this.tabTargets.indexOf(event.currentTarget)
    if (i < 0 || this.#disabled(i)) return
    this.#activate(i, { focus: true })
  }

  // keydown on a tab (bound per-trigger; event.currentTarget is the focused tab)
  navigate(event) {
    const current = this.tabTargets.indexOf(event.currentTarget)
    if (current < 0) return
    let next = null
    switch (event.key) {
      case "ArrowRight": next = this.#adjacent(current, 1); break
      case "ArrowLeft":  next = this.#adjacent(current, -1); break
      case "Home":       next = this.#firstEnabled(); break
      case "End":        next = this.#lastEnabled(); break
      default: return
    }
    if (next === null) return
    event.preventDefault()
    this.#activate(next, { focus: true })
  }

  #adjacent(from, delta) {
    const n = this.tabTargets.length
    if (n === 0) return null
    let i = from
    for (let k = 0; k < n; k++) {
      i = (i + delta + n) % n
      if (!this.#disabled(i)) return i
    }
    // Only the current tab is enabled — stay put (APG: wrap brings you back to yourself).
    return this.#disabled(from) ? null : from
  }

  #firstEnabled() {
    for (let i = 0; i < this.tabTargets.length; i++) if (!this.#disabled(i)) return i
    return null
  }

  #lastEnabled() {
    for (let i = this.tabTargets.length - 1; i >= 0; i--) if (!this.#disabled(i)) return i
    return null
  }

  #disabled(i) {
    const tab = this.tabTargets[i]
    return !tab || tab.getAttribute("aria-disabled") === "true"
  }

  #activate(index, { focus }) {
    this.indexValue = index
    this.tabTargets.forEach((tab, i) => {
      const active = i === index
      tab.setAttribute("aria-selected", active ? "true" : "false")
      tab.setAttribute("tabindex", active ? "0" : "-1")
      tab.dataset.state = active ? "active" : "inactive"
    })
    this.panelTargets.forEach((panel, i) => { panel.hidden = i !== index })
    if (focus) this.tabTargets[index]?.focus()
  }
}

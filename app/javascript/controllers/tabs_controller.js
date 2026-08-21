import { Controller } from "@hotwired/stimulus"

// WAI-ARIA APG tabs. Roving tabindex across the role=tab buttons; the active tab is
// tabindex=0, the rest -1. Arrow keys wrap and skip aria-disabled tabs; Home/End jump to
// the first/last enabled tab; a click activates.
//
// Two axes, both defaulting to what this shipped with:
//   orientation — horizontal (←/→) or vertical (↑/↓). The OTHER axis is deliberately inert,
//     per APG: a horizontal tablist ignoring ↑/↓ leaves those keys to the page.
//   activation  — automatic (focus reveals the panel) or manual (arrows move focus only,
//     Enter/Space reveals). Panels render inline/eager, so automatic has no latency and
//     stays the default; manual exists for panels that are expensive to reveal, where
//     activating on every arrow press would thrash.
//
// Under automatic, Enter/Space are no-ops because focus already activated.
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = {
    index: Number,
    orientation: { type: String, default: "horizontal" },
    activation: { type: String, default: "automatic" }
  }

  connect() {
    const start = this.#disabled(this.indexValue) ? (this.#firstEnabled() ?? 0) : this.indexValue
    this.#activate(start, { focus: false })
  }

  select(event) {
    const i = this.tabTargets.indexOf(event.currentTarget)
    if (i < 0 || this.#disabled(i)) return
    this.#activate(i, { focus: true })
  }

  // Bound per-trigger, so event.currentTarget is the focused tab.
  navigate(event) {
    const current = this.tabTargets.indexOf(event.currentTarget)
    if (current < 0) return
    const vertical = this.orientationValue === "vertical"
    const forward = vertical ? "ArrowDown" : "ArrowRight"
    const back = vertical ? "ArrowUp" : "ArrowLeft"

    // Manual activation: Enter/Space reveal whatever the arrows moved focus to.
    if (this.activationValue === "manual" && (event.key === "Enter" || event.key === " ")) {
      event.preventDefault()
      this.#activate(current, { focus: true })
      return
    }

    let next = null
    switch (event.key) {
      case forward: next = this.#adjacent(current, 1); break
      case back:    next = this.#adjacent(current, -1); break
      case "Home":  next = this.#firstEnabled(); break
      case "End":   next = this.#lastEnabled(); break
      default: return
    }
    if (next === null) return
    event.preventDefault()

    if (this.activationValue === "manual") {
      this.#focusOnly(next)
    } else {
      this.#activate(next, { focus: true })
    }
  }

  // Manual mode moves the tab stop with focus (APG) but leaves aria-selected and the
  // panels alone until the user commits.
  #focusOnly(index) {
    this.tabTargets.forEach((tab, i) => tab.setAttribute("tabindex", i === index ? "0" : "-1"))
    this.tabTargets[index]?.focus()
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

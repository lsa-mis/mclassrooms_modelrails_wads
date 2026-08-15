import { Controller } from "@hotwired/stimulus"

// Command palette behavior. Owns the WAI-ARIA APG combobox + listbox contract:
// the input is the combobox (keeps DOM focus), the list is the listbox, and each
// `[data-command-value]` item is promoted to a `role="option"` with a stable id.
// Navigation is `aria-activedescendant`-based — ↑/↓/Home/End move the *active*
// option without moving DOM focus off the input; Enter activates it. Filtering
// hides non-matching options and toggles the empty-state live region.
export default class extends Controller {
  static targets = ["panel", "input", "list", "empty"]

  connect() {
    this._onKeydown = this._onKeydown.bind(this)
    document.addEventListener("keydown", this._onKeydown)
    this._optionId = 0
    this.activeId = null
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
  }

  _onKeydown(event) {
    if (event.key === "k" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault()
      this.panelTarget.hidden ? this.open() : this.close()
    }
  }

  open() {
    this.panelTarget.hidden = false
    document.body.style.overflow = "hidden"
    this.inputTarget.value = ""
    this.inputTarget.setAttribute("aria-expanded", "true")
    this._tagOptions()
    this.inputTarget.focus()
    this.filter()
  }

  close() {
    this.panelTarget.hidden = true
    document.body.style.overflow = ""
    this.inputTarget.setAttribute("aria-expanded", "false")
    this._setActive(null)
  }

  filter() {
    const query = this.inputTarget.value.toLowerCase().trim()
    const items = this.options
    items.forEach(item => {
      item.hidden = query.length > 0 && !item.dataset.commandValue.toLowerCase().includes(query)
    })

    this.listTarget.querySelectorAll("[data-command-group]").forEach(group => {
      const hasVisible = Array.from(group.querySelectorAll("[data-command-value]")).some(i => !i.hidden)
      group.hidden = !hasVisible
    })

    const visible = items.filter(i => !i.hidden)
    this.emptyTarget.hidden = visible.length > 0
    // Keep the active option valid as the visible set narrows.
    this._setActive(visible[0] || null)
  }

  // ↑/↓/Home/End move the active option; Enter activates it. DOM focus stays on
  // the input (combobox pattern), so we drive selection via aria-activedescendant.
  navigate(event) {
    const visible = this.options.filter(i => !i.hidden)
    if (!visible.length) return

    const current = visible.findIndex(el => el.id === this.activeId)
    let next = null

    switch (event.key) {
      case "ArrowDown":
        next = visible[(current + 1) % visible.length]
        break
      case "ArrowUp":
        next = visible[(current - 1 + visible.length) % visible.length]
        break
      case "Home":
        next = visible[0]
        break
      case "End":
        next = visible[visible.length - 1]
        break
      case "Enter": {
        const active = visible[current]
        if (active) {
          event.preventDefault()
          active.click()
        }
        return
      }
      default:
        return
    }

    event.preventDefault()
    this._setActive(next)
    next.scrollIntoView({ block: "nearest" })
  }

  get options() {
    return Array.from(this.listTarget.querySelectorAll("[data-command-value]"))
  }

  // Promote caller-supplied items to listbox options with stable ids (the markup
  // stays plain — the role/id contract is applied here so callers can't break it).
  _tagOptions() {
    this.options.forEach(item => {
      item.setAttribute("role", "option")
      if (!item.id) item.id = `command-option-${this._optionId++}`
    })
    // An <hr> separator's implicit role="separator" is an illegal child of
    // role="listbox" (axe aria-required-children, critical — caught by the
    // open-state audit, #463). Neutralize caller-supplied separators the same
    // way options are promoted: the contract is applied here so markup can't
    // break it.
    this.listTarget.querySelectorAll("hr").forEach(hr => {
      hr.setAttribute("role", "presentation")
      hr.setAttribute("aria-hidden", "true")
    })
  }

  _setActive(item) {
    this.options.forEach(el => el.setAttribute("aria-selected", el === item ? "true" : "false"))
    if (item) {
      this.activeId = item.id
      this.inputTarget.setAttribute("aria-activedescendant", item.id)
    } else {
      this.activeId = null
      this.inputTarget.removeAttribute("aria-activedescendant")
    }
  }
}

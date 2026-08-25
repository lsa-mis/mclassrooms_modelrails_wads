import { Controller } from "@hotwired/stimulus"
import { nextActive } from "keyboard/keyboard_nav"
import { commandScore } from "search/command_score"

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
    this._captureAuthoredOrder()
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

  // The authored order is captured once, because sorting is destructive: after the first
  // ranked query the DOM no longer knows what the caller wrote.
  _captureAuthoredOrder() {
    this._authored ||= this.options.map(item => [item, item.parentElement, Array.from(item.parentElement.children).indexOf(item)])
  }

  _restoreAuthoredOrder() {
    if (!this._authored) return
    this._authored.forEach(([item, parent, index]) => {
      const at = parent.children[index]
      if (at !== item) parent.insertBefore(item, at || null)
    })
  }

  // Rank WITHIN each group only. Group order is authored intent — a caller who put
  // "Pages" above "Actions" meant that — and reordering groups by best score makes the
  // palette's shape move under the user between keystrokes.
  _rankWithinGroups(scored) {
    const byGroup = new Map()
    scored.forEach(entry => {
      const group = entry.item.parentElement
      if (!byGroup.has(group)) byGroup.set(group, [])
      byGroup.get(group).push(entry)
    })

    byGroup.forEach((entries, group) => {
      entries.sort((a, b) => b.score - a.score).forEach(({ item }) => group.appendChild(item))
    })
  }

  filter() {
    const query = this.inputTarget.value.trim()
    const items = this.options

    if (query.length === 0) {
      // Restore the order the author wrote. Ranking is only meaningful against a query;
      // with none, the caller's grouping is the intended reading order.
      items.forEach(item => { item.hidden = false })
      this._restoreAuthoredOrder()
    } else {
      // `data-command-keywords` lets an item be found by a synonym it does not display
      // ("configuration" finding Settings) without polluting its visible label.
      const scored = items.map(item => ({
        item,
        score: commandScore(item.dataset.commandValue, query, [item.dataset.commandKeywords || ""])
      }))
      scored.forEach(({ item, score }) => { item.hidden = score === 0 })
      this._rankWithinGroups(scored.filter(s => s.score > 0))
    }

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
      case "ArrowUp":
      case "Home":
      case "End":
        // ArrowUp's no-active-option entry is parity with combobox, not a live path
        // here: filter() re-seeds the active option on every open and input, and the
        // input lives inside the panel. test_stays_closed_on_arrow_up_after_escape
        // pins that. Sharing the movement keeps the pair from drifting again.
        next = nextActive(visible, current, event.key)
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
  // The host element's id is unique per instance; deriving the prefix from it keeps
  // option ids unique across several instances on one page, which aria-activedescendant
  // depends on to point at the right node.
  get _idPrefix() {
    return this.element.id || "command"
  }

  _tagOptions() {
    this.options.forEach(item => {
      item.setAttribute("role", "option")
      if (!item.id) item.id = `${this._idPrefix}-option-${this._optionId++}`
    })

    // An <hr> separator's implicit role="separator" is an illegal child of
    // role="listbox" (axe aria-required-children, critical). SEPARATOR and the
    // docs example both hand callers exactly this markup, so the contract is
    // applied here — where markup cannot break it — rather than asked for.
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

import { Controller } from "@hotwired/stimulus"
import { nextActive } from "keyboard/keyboard_nav"
import * as topLayer from "overlays/top_layer"

// Autocomplete-select behavior. Owns the WAI-ARIA APG combobox + listbox
// contract: the text input is the combobox (keeps DOM focus) and the popup is the
// listbox. Each option already ships as a `role="option"`; navigation is
// `aria-activedescendant`-based — ↑/↓/Home/End move the *active* option without
// moving DOM focus off the input, Enter selects it, Escape closes. Filtering hides
// non-matching options and toggles the empty-state live region.
export default class extends Controller {
  static targets = ["input", "hidden", "panel", "list", "option", "empty"]

  connect() {
    this._optionId = 0
    this._tagOptions()
    this._syncSelected()
  }

  open() {
    this.panelTarget.hidden = false
    // No-op unless anchor-positioned (`position: fixed`); top_layer.js refuses the
    // pre-Baseline `absolute` fallback, where promotion would tear the panel off-screen.
    topLayer.enable(this.panelTarget)
    topLayer.show(this.panelTarget)
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.filter()
  }

  close() {
    topLayer.hide(this.panelTarget)
    topLayer.disable(this.panelTarget)
    this.panelTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this._setActive(null)
    const selected = this.optionTargets.find(o => o.dataset.comboboxValue === this.hiddenTarget.value)
    this.inputTarget.value = selected ? selected.dataset.comboboxLabel : ""
  }

  filter() {
    const query = this.inputTarget.value.toLowerCase().trim()
    const visible = this.optionTargets.filter(option => {
      const match = option.dataset.comboboxLabel.toLowerCase().includes(query)
      option.hidden = !match
      return match
    })
    this.emptyTarget.hidden = visible.length > 0
    // Keep the active option valid as the visible set narrows.
    this._setActive(visible[0] || null)
  }

  // ↑/↓/Home/End move the active option; Enter selects it; Escape closes. DOM
  // focus stays on the input (combobox pattern), so selection is driven via
  // aria-activedescendant rather than moving focus onto options.
  navigate(event) {
    if (event.key === "Escape") {
      this.close()
      return
    }

    // Reopen handling runs BEFORE the visible set is computed: after Escape
    // on a zero-match filter the stale option.hidden states would leave
    // `visible` empty, and an early return here locked the keyboard out of
    // ever reopening (only a printable keystroke recovered). open() re-runs
    // filter() against the restored committed label; entry then follows APG —
    // ArrowDown activates the FIRST visible option, ArrowUp the LAST.
    if ((event.key === "ArrowDown" || event.key === "ArrowUp") && this.panelTarget.hidden) {
      event.preventDefault()
      this.open()
      const reopened = this.optionTargets.filter(o => !o.hidden)
      if (!reopened.length) return
      this._setActive(event.key === "ArrowUp" ? reopened[reopened.length - 1] : reopened[0])
      return
    }

    const visible = this.optionTargets.filter(o => !o.hidden)
    if (!visible.length) return

    const current = visible.findIndex(el => el.id === this.activeId)
    let next = null

    switch (event.key) {
      case "ArrowDown":
      case "ArrowUp":
      case "Home":
      case "End":
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

  select(event) {
    const { comboboxValue, comboboxLabel } = event.currentTarget.dataset
    this.hiddenTarget.value = comboboxValue
    this.inputTarget.value = comboboxLabel
    this._syncSelected()
    this.close()
  }

  closeOnClickOutside({ target }) {
    if (!this.element.contains(target)) this.close()
  }

  // Promote options to stable ids so aria-activedescendant can reference them
  // (the markup ships role="option"; the id contract is applied here).
  // The host element's id is unique per instance; deriving the prefix from it keeps
  // option ids unique across several instances on one page, which aria-activedescendant
  // depends on to point at the right node.
  get _idPrefix() {
    return this.element.id || "combobox"
  }

  _tagOptions() {
    this.optionTargets.forEach(option => {
      if (!option.id) option.id = `${this._idPrefix}-option-${this._optionId++}`
    })
  }

  // Reflect the committed value onto aria-selected (the chosen option, not the
  // keyboard-highlighted one — that's aria-activedescendant).
  _syncSelected() {
    this.optionTargets.forEach(option => {
      option.setAttribute(
        "aria-selected",
        option.dataset.comboboxValue === this.hiddenTarget.value ? "true" : "false"
      )
    })
  }

  // Track the keyboard-highlighted option via aria-activedescendant; DOM focus
  // never leaves the input.
  _setActive(option) {
    if (option) {
      this.activeId = option.id
      this.inputTarget.setAttribute("aria-activedescendant", option.id)
    } else {
      this.activeId = null
      this.inputTarget.removeAttribute("aria-activedescendant")
    }
  }
}

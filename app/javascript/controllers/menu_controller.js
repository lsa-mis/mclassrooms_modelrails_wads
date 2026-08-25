import { Controller } from "@hotwired/stimulus"
import { TypeAhead } from "keyboard/keyboard_nav"
import * as topLayer from "overlays/top_layer"

// Behavior for the menu-pattern band. dropdown_menu is the exemplar/home; context_menu
// and menubar reuse this via EXTRA_STIMULUS. CSS owns positioning (anchor positioning);
// this owns the WAI-ARIA APG menu-button contract: open/close + aria-expanded sync,
// roving-tabindex item navigation (arrows / Home / End / type-ahead, skipping
// aria-disabled), and Escape / Tab / outside-click dismissal with focus restoration.
// Activation is native: each item is a <button>/<a>, so Enter/Space/click fire its own
// action — `activate` only blocks disabled items and closes the menu.
export default class extends Controller {
  static targets = ["trigger", "menu", "item"]
  static values = { open: { type: Boolean, default: false } }

  connect() {
    this._typeAhead = new TypeAhead()
  }

  disconnect() {
    this._typeAhead.cancel()
  }

  // --- open / close -------------------------------------------------------

  toggle(event) {
    if (event) event.preventDefault()
    this.openValue ? this.close() : this.open()
  }

  // Trigger keydown: Enter / Space / ArrowDown open and focus the first item;
  // ArrowUp opens and focuses the last.
  triggerKeydown(event) {
    if (["Enter", " ", "ArrowDown"].includes(event.key)) {
      event.preventDefault()
      this.open()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.open({ focus: "last" })
    }
  }

  open({ focus = "first" } = {}) {
    if (this.openValue) return
    this.openValue = true
    this.menuTarget.hidden = false
    // Safe here because placement is CSS anchor positioning (already `position: fixed`
    // against the viewport), so the top layer changes paint order only.
    topLayer.enable(this.menuTarget)
    topLayer.show(this.menuTarget)
    this.triggerTarget.setAttribute("aria-expanded", "true")
    focus === "last" ? this.focusLast() : this.focusFirst()
  }

  close({ restoreFocus = true } = {}) {
    if (!this.openValue) return
    this.openValue = false
    // A submenu is its own controller, so it does not close just because this one did.
    // Left alone it stays popover-open with aria-expanded="true" and reappears already
    // expanded the next time this menu opens.
    this.#closeSubmenus()
    topLayer.hide(this.menuTarget)
    topLayer.disable(this.menuTarget)
    this.menuTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    if (restoreFocus) this.triggerTarget.focus()
  }

  #closeSubmenus() {
    this.element.querySelectorAll("[data-controller~='submenu']")
      .forEach((el) => el.dispatchEvent(new CustomEvent("menu:close")))
  }

  closeOnClickOutside(event) {
    if (this.openValue && !this.element.contains(event.target)) {
      this.close({ restoreFocus: false })
    }
  }

  // --- roving navigation --------------------------------------------------

  get enabledItems() {
    return this.itemTargets.filter((el) => el.getAttribute("aria-disabled") !== "true")
  }

  focusItem(item) {
    this.itemTargets.forEach((el) => el.setAttribute("tabindex", el === item ? "0" : "-1"))
    item.focus()
  }

  focusFirst() {
    const items = this.enabledItems
    if (items.length) this.focusItem(items[0])
  }

  focusLast() {
    const items = this.enabledItems
    if (items.length) this.focusItem(items[items.length - 1])
  }

  // Menu keydown — delegated from items via bubbling.
  navigate(event) {
    const items = this.enabledItems
    if (!items.length) return
    const current = items.indexOf(document.activeElement)

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.focusItem(items[(current + 1) % items.length])
        break
      case "ArrowUp":
        event.preventDefault()
        // No item focused (current === -1): the panel itself holds focus —
        // its tabindex="-1" catches clicks on padding or a separator. APG says
        // ArrowUp enters at the LAST item; the modulo alone lands one short
        // of it. Same correction as combobox/command; typeAhead already
        // guards -1 with Math.max — this was the one unguarded path.
        this.focusItem(current === -1 ? items[items.length - 1] : items[(current - 1 + items.length) % items.length])
        break
      case "Home":
        event.preventDefault()
        this.focusItem(items[0])
        break
      case "End":
        event.preventDefault()
        this.focusItem(items[items.length - 1])
        break
      case "Escape":
        event.preventDefault()
        this.close()
        break
      case "Tab":
        // Let focus leave naturally to the next page element, but close the menu.
        this.close({ restoreFocus: false })
        break
      case "Enter":
      case " ":
        // Let the focused <button>/<a> activate natively (→ click → activate).
        break
      default:
        if (event.key.length === 1) this.typeAhead(event.key)
    }
  }

  typeAhead(char) {
    this._typeAhead.push(char)

    // Pre-filtered: menu focuses by element, so disabled items can leave the set.
    const items = this.enabledItems
    const i = this._typeAhead.match(items, Math.max(0, items.indexOf(document.activeElement)))
    if (i !== -1) this.focusItem(items[i])
  }

  // --- activation ---------------------------------------------------------

  activate(event) {
    const item = event.currentTarget
    if (item.getAttribute("aria-disabled") === "true") {
      event.preventDefault()
      return
    }

    // Checkable items change state and leave the menu open (APG menu pattern), so a
    // multi-select view menu is usable in one pass. Plain items still close.
    switch (item.getAttribute("role")) {
      case "menuitemcheckbox":
        item.setAttribute("aria-checked", String(item.getAttribute("aria-checked") !== "true"))
        return
      case "menuitemradio": {
        const group = item.dataset.menuRadioGroup
        this.itemTargets
          .filter((el) => el.dataset.menuRadioGroup === group)
          .forEach((el) => el.setAttribute("aria-checked", String(el === item)))
        return
      }
    }

    this.close()
  }

  // --- context_menu: pointer / keyboard positioning -----------------------
  // (used by context_menu via EXTRA_STIMULUS; dropdown_menu never wires these)

  // Right-click: open the menu at the pointer. Re-opens at the new point if
  // already open (a second right-click moves the menu).
  openAt(event) {
    event.preventDefault()
    this.positionAt(event.clientX, event.clientY)
    this.openValue ? this.focusFirst() : this.open()
  }

  // Keyboard parity (Shift+F10 or the ContextMenu key) while the host has focus —
  // right-click is pointer-only, so this is required (WCAG 2.1.1). No pointer
  // coordinates, so position near the host (the trigger target's rect).
  openContextKey(event) {
    if (!((event.shiftKey && event.key === "F10") || event.key === "ContextMenu")) return
    event.preventDefault()
    const rect = this.triggerTarget.getBoundingClientRect()
    this.positionAt(rect.left, rect.bottom)
    this.openValue ? this.focusFirst() : this.open()
  }

  positionAt(x, y) {
    this.menuTarget.style.left = `${x}px`
    this.menuTarget.style.top = `${y}px`
  }
}

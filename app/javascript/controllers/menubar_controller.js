import { Controller } from "@hotwired/stimulus"

// Coordinator for the WAI-ARIA APG menubar. Each menubar item's submenu is its OWN `menu`
// controller (reused via EXTRA_STIMULUS, like dropdown_menu/context_menu); THIS controller
// owns only the horizontal layer — roving tabindex across the bar items, ←/→/Home/End/
// type-ahead, and opening/closing adjacent submenus via Stimulus outlets.
//
// Key-routing is implicit (no mode flag): keys the open submenu's `menu#navigate` claims are
// preventDefaulted, so we skip them via `event.defaultPrevented`; ←/→ are NEVER claimed by
// `menu` (no ArrowLeft/Right case there) so they bubble here.
// INVARIANT: never add an ArrowLeft/ArrowRight case to `menu#navigate` — the menubar relies
// on ←/→ bubbling unclaimed.
export default class extends Controller {
  static targets = ["item"]   // the bar-item buttons (each is also a `menu` trigger)
  static outlets = ["menu"]   // the per-item submenu `menu` controllers (one per item)

  connect() {
    this.typeBuffer = ""
    this.typeTimer = null
    this.resetRovingTabindex()
  }

  disconnect() {
    if (this.typeTimer) clearTimeout(this.typeTimer)
  }

  // --- roving tabindex across bar items -----------------------------------

  get enabledIndexes() {
    return this.itemTargets
      .map((el, i) => (el.getAttribute("aria-disabled") === "true" ? -1 : i))
      .filter((i) => i >= 0)
  }

  resetRovingTabindex() {
    const first = this.enabledIndexes[0] ?? 0
    this.itemTargets.forEach((el, i) => el.setAttribute("tabindex", i === first ? "0" : "-1"))
  }

  // Whichever bar item gains focus becomes the single tabbable item (covers click,
  // Escape-return, Tab, and arrow moves uniformly). Focus inside a submenu leaves roving.
  syncRoving(event) {
    const i = this.itemTargets.indexOf(event.target)
    if (i < 0) return
    this.itemTargets.forEach((el, k) => el.setAttribute("tabindex", k === i ? "0" : "-1"))
  }

  focusItem(index) {
    this.itemTargets.forEach((el, i) => el.setAttribute("tabindex", i === index ? "0" : "-1"))
    this.itemTargets[index].focus()
  }

  // The "current" bar-item index: the open submenu's item if one is open, else the focused
  // bar button, else the first enabled item.
  currentIndex() {
    const open = this.menuOutlets.findIndex((o) => o.openValue)
    if (open >= 0) return open
    const focused = this.itemTargets.indexOf(document.activeElement)
    return focused >= 0 ? focused : (this.enabledIndexes[0] ?? 0)
  }

  // --- horizontal navigation (bar level) ----------------------------------

  navigate(event) {
    if (event.defaultPrevented) return // the open submenu's menu#navigate already handled it
    switch (event.key) {
      case "ArrowRight":
        event.preventDefault()
        this.moveBy(1)
        break
      case "ArrowLeft":
        event.preventDefault()
        this.moveBy(-1)
        break
      case "Home":
        event.preventDefault()
        if (this.enabledIndexes.length) this.focusItem(this.enabledIndexes[0])
        break
      case "End":
        event.preventDefault()
        if (this.enabledIndexes.length) this.focusItem(this.enabledIndexes[this.enabledIndexes.length - 1])
        break
      default:
        // Bar-level type-ahead ONLY when no submenu is open (an open submenu owns letters;
        // its menu#typeAhead runs without preventDefault, so guard against a double-match).
        if (
          event.key.length === 1 &&
          !event.ctrlKey && !event.metaKey && !event.altKey &&
          this.menuOutlets.every((o) => !o.openValue)
        ) {
          this.typeAhead(event.key)
        }
    }
  }

  // Move to the adjacent enabled bar item (wrapping). If a submenu was open, this is the
  // menubar "follow": close the current submenu and open the adjacent one (focus its first
  // item). Otherwise just move roving focus.
  // INVARIANT: itemTargets[i] and menuOutlets[i] are co-indexed by DOM order — one bar-item
  // button and one menu outlet per menubar_menu. Verified by the app 0b.
  moveBy(delta) {
    const n = this.itemTargets.length
    if (n === 0) return
    const wasOpen = this.menuOutlets.findIndex((o) => o.openValue)
    const cur = this.currentIndex()
    let next = cur
    do {
      next = (next + delta + n) % n
    } while (this.itemTargets[next].getAttribute("aria-disabled") === "true" && next !== cur)
    const fromMenu = wasOpen >= 0 ? this.menuOutlets[wasOpen] : null
    if (fromMenu) fromMenu.close({ restoreFocus: false })
    this.focusItem(next)
    if (fromMenu && this.menuOutlets[next]) this.menuOutlets[next].open({ focus: "first" })
  }

  typeAhead(char) {
    this.typeBuffer += char.toLowerCase()
    if (this.typeTimer) clearTimeout(this.typeTimer)
    this.typeTimer = setTimeout(() => { this.typeBuffer = "" }, 1000)
    const n = this.itemTargets.length
    const start = Math.max(0, this.itemTargets.indexOf(document.activeElement))
    for (let k = 1; k <= n; k++) {
      const i = (start + k) % n
      const el = this.itemTargets[i]
      if (el.getAttribute("aria-disabled") === "true") continue
      if (el.textContent.trim().toLowerCase().startsWith(this.typeBuffer)) {
        this.focusItem(i)
        return
      }
    }
  }
}

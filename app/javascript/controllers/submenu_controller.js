import { Controller } from "@hotwired/stimulus"
import * as topLayer from "overlays/top_layer"

// Nested menu inside a `menu` controller. Deliberately a DISTINCT identifier: the
// sub-trigger has to be `data-menu-target="item"` so it stays in the parent's arrow-key
// rotation, while also being this controller's trigger. Two identifiers, one element,
// no target collision.
//
// Keyboard model is the WAI-ARIA APG submenu pattern — ArrowRight/Enter opens and moves
// focus in, ArrowLeft/Escape closes and returns focus to the sub-trigger. Escape is not
// propagated, so it closes only this layer and leaves the parent menu standing.
export default class extends Controller {
  static targets = ["trigger", "panel", "item"]
  static values = { open: { type: Boolean, default: false } }

  disconnect() {
    if (this.closeTimer) clearTimeout(this.closeTimer)
  }

  toggle(event) {
    event.preventDefault()
    this.openValue ? this.close() : this.open({ focus: false })
  }

  open({ focus = false } = {}) {
    if (this.closeTimer) {
      clearTimeout(this.closeTimer)
      this.closeTimer = null
    }
    if (!this.openValue) {
      this.openValue = true
      this.panelTarget.hidden = false
      // Placement is anchor positioning, so the panel is already viewport-positioned and
      // promotion changes paint order only.
      topLayer.enable(this.panelTarget)
      topLayer.show(this.panelTarget)
      this.triggerTarget.setAttribute("aria-expanded", "true")
    }
    if (focus) this.focusItem(this.enabledItems[0])
  }

  close({ restoreFocus = false } = {}) {
    if (!this.openValue) return
    this.openValue = false
    topLayer.hide(this.panelTarget)
    topLayer.disable(this.panelTarget)
    this.panelTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
    if (restoreFocus) this.triggerTarget.focus()
  }

  // The parent menu closing is not a dismissal the user aimed at this layer, so focus
  // stays wherever the parent puts it.
  forceClose() {
    this.close({ restoreFocus: false })
  }

  // Hovering away closes after a beat so the pointer can cross the gap between the
  // sub-trigger and its panel without the submenu vanishing.
  scheduleClose() {
    this.closeTimer = setTimeout(() => this.close(), 150)
  }

  triggerKeydown(event) {
    switch (event.key) {
      case "ArrowRight":
      case "Enter":
      case " ":
        event.preventDefault()
        event.stopPropagation()
        this.open({ focus: true })
        break
    }
  }

  navigate(event) {
    const items = this.enabledItems
    if (!items.length) return
    const current = items.indexOf(document.activeElement)

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        event.stopPropagation()
        this.focusItem(items[(current + 1) % items.length])
        break
      case "ArrowUp":
        event.preventDefault()
        event.stopPropagation()
        this.focusItem(items[(current - 1 + items.length) % items.length])
        break
      case "ArrowLeft":
      case "Escape":
        // Stop here so the parent menu keeps its own Escape handling for its own layer.
        event.preventDefault()
        event.stopPropagation()
        this.close({ restoreFocus: true })
        break
    }
  }

  activate(event) {
    if (event.currentTarget.getAttribute("aria-disabled") === "true") {
      event.preventDefault()
      return
    }
    this.close()
  }

  get enabledItems() {
    return this.itemTargets.filter((el) => el.getAttribute("aria-disabled") !== "true")
  }

  focusItem(item) {
    if (!item) return
    this.itemTargets.forEach((el) => el.setAttribute("tabindex", el === item ? "0" : "-1"))
    item.focus()
  }
}

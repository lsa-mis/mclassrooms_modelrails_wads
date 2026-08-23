import { Controller } from "@hotwired/stimulus"

// Drag-to-dismiss for the drawer. The component already rendered a grab handle; without
// this it was an affordance that promised draggability and ignored the pointer.
//
// SCOPE: the drag starts from the HANDLE only, never the body. Dragging from anywhere in
// the panel means distinguishing a drag from a scroll on every pointerdown, and getting
// that wrong breaks scrolling inside the drawer — a worse failure than not having drag.
// The handle is also the only part a user is invited to grab.
//
// Drag is an ADDITION. Escape and the close button are untouched: this is pointer-only,
// so it is unavailable to keyboard and switch users by nature and can never be the sole
// way out.
export default class extends Controller {
  static targets = ["panel"]
  static values = {
    // A FRACTION of the panel's own height, not a fixed pixel distance. A short drawer
    // sits close to the bottom of the screen, so there is only its own height of travel
    // available — a fixed 120px threshold is literally unreachable on one, and the drawer
    // would refuse to dismiss no matter how far the user dragged.
    fraction: { type: Number, default: 0.25 },
    // Below this the gesture reads as a nudge rather than intent, however short the panel.
    minimum: { type: Number, default: 48 },
    // A flick dismisses regardless of distance: px per ms.
    velocity: { type: Number, default: 0.5 }
  }

  // The panel's open position is an inline transform set by `modal` when it animates in.
  // Dragging writes to the same property, so the rest position has to be restored rather
  // than cleared — clearing it drops the panel back to the class-level `translate-y-full`
  // and the drawer vanishes while still open.
  static OPEN_TRANSFORM = "translateY(0)"

  start(event) {
    if (!this.hasPanelTarget) return

    this.dragging = true
    this.startY = event.clientY
    this.startedAt = event.timeStamp
    this.offset = 0
    this.panelTarget.style.transition = "none"
  }

  // Bound at document level, not on the handle: once a drag starts the pointer routinely
  // leaves the handle, and listeners scoped to it stop receiving moves mid-gesture.
  move(event) {
    if (!this.dragging) return

    // Downward only. Dragging up would lift the drawer off its own edge.
    this.offset = Math.max(0, event.clientY - this.startY)
    this.panelTarget.style.transform = `translate3d(0, ${this.offset}px, 0)`
  }

  end(event) {
    if (!this.dragging) return
    this.dragging = false
    this.panelTarget.style.transition = ""

    // The pointerup position, not the last pointermove: browsers coalesce moves under
    // load, and a fast flick is exactly when they drop the most — so the last move can
    // report a fraction of the distance the user actually travelled.
    const travelled = Math.max(0, event.clientY - this.startY)
    const elapsed = event.timeStamp - this.startedAt
    const velocity = elapsed > 0 ? travelled / elapsed : 0

    const threshold = Math.max(this.minimumValue, this.panelTarget.offsetHeight * this.fractionValue)

    if (travelled >= threshold || velocity >= this.velocityValue) {
      // Hand off to the modal controller rather than closing the dialog directly, so the
      // exit animation and focus restoration still run.
      this.dispatch("dismiss")
    } else {
      this.#springBack()
    }
  }

  // Leave no inline transform behind: the panel's open/closed position is the
  // component's business, and a stale transform would fight it on the next open.
  #springBack() {
    this.panelTarget.style.transform = this.constructor.OPEN_TRANSFORM
    this.offset = 0
  }
}

import { Controller } from "@hotwired/stimulus"

// Copies the readonly value to the clipboard and confirms in two carriers: the check
// glyph and the pre-registered polite status region. Failure — a rejected promise, no
// secure context, an empty value — selects the value and writes the failure string into
// the assertive region; it never claims a success it cannot prove. The visible button
// text is never touched (label-in-name). Both regions are cleared at the START of a copy
// so every announcement is a fresh "" → text mutation; only `state` (the icon) reverts
// on the timer. connect() and turbo:before-cache reset everything, so a Turbo snapshot
// never restores mid-feedback state.
export default class extends Controller {
  static targets = ["source", "status", "error", "copyIcon", "successIcon"]
  static values = {
    copied: String,
    failed: String,
    state: { type: String, default: "idle" },
    duration: { type: Number, default: 2000 }
  }

  connect() {
    this.timer = null
    this.boundReset = this.reset.bind(this)
    document.addEventListener("turbo:before-cache", this.boundReset)
    this.reset()
  }

  disconnect() {
    clearTimeout(this.timer)
    document.removeEventListener("turbo:before-cache", this.boundReset)
  }

  async copy() {
    if (this.stateValue !== "idle") return
    this.#clearRegions()
    const value = this.sourceTarget.value

    try {
      if (!value) throw new Error("empty-value")
      if (!navigator.clipboard) throw new Error("clipboard-unavailable")
      await navigator.clipboard.writeText(value)
      this.#settle("copied", this.statusTarget, this.copiedValue, { value })
    } catch (error) {
      // Yielding here gives the #clearRegions() write its own mutation batch, observable to
      // a MutationObserver; whether AT re-announces an identical string is a manual check.
      await Promise.resolve()
      this.sourceTarget.select()
      this.#settle("failed", this.errorTarget, this.failedValue, { value, error })
    }
  }

  // Applies idle unconditionally rather than only through stateValue's setter: a DOM
  // move (Stimulus disconnect/reconnect) can land here while the underlying
  // data-copy-state-value attribute is ALREADY "idle" (e.g. a stale data-state mirror
  // left over from a manual DOM edit, or a cached snapshot). Stimulus only invokes
  // stateValueChanged on an actual attribute change, so a reset that relied solely on
  // `this.stateValue = "idle"` would silently no-op and leave the mirror stale.
  reset() {
    clearTimeout(this.timer)
    this.timer = null
    this.stateValue = "idle"
    this.#applyState("idle")
    this.#clearRegions()
  }

  stateValueChanged(state) {
    this.#applyState(state)
  }

  #settle(state, region, message, detail) {
    this.stateValue = state
    region.textContent = message
    this.dispatch(state, { detail })
    this.timer = setTimeout(() => { this.stateValue = "idle" }, this.durationValue)
  }

  #applyState(state) {
    this.element.dataset.state = state
    // Not `.hidden = …`: the icons are <svg> targets, and SVGElement does not reflect
    // the boolean `hidden` IDL property to the content attribute the way HTMLElement
    // does — the assignment silently no-ops. Toggle the attribute directly instead.
    this.#toggleHidden(this.copyIconTarget, state === "copied")
    this.#toggleHidden(this.successIconTarget, state !== "copied")
  }

  #toggleHidden(element, hidden) {
    if (hidden) {
      element.setAttribute("hidden", "")
    } else {
      element.removeAttribute("hidden")
    }
  }

  #clearRegions() {
    this.statusTarget.textContent = ""
    this.errorTarget.textContent = ""
  }
}

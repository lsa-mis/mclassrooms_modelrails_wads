import { Controller } from "@hotwired/stimulus"

// Announces settings-hub context changes (identity vs workspace context switch)
// to assistive tech via the polite aria-live region this controller mounts on.
//
// Why turbo:render (not turbo:morph-rendered): it fires once per full page
// render — covering both initial load and morph-driven updates.
//
// Why dedup on `lastKind`: the previous implementation cleared + re-wrote on
// every render, which forced AT to re-announce even when navigating
// identity→identity or workspace→workspace. Screen readers handle the
// duplicate-content rule inconsistently, but the better fix is to only
// announce on actual transitions — first entry into the hub OR a kind change.
// First page load (no prior `lastKind`) is silent because the user knows
// where they just landed; announcement is for *transitions*.
export default class extends Controller {
  static values = {
    identity: String,
    workspace: String,
  }

  connect() {
    this.lastKind = null
    this.boundOnRender = this.onRender.bind(this)
    document.addEventListener("turbo:render", this.boundOnRender)
  }

  disconnect() {
    document.removeEventListener("turbo:render", this.boundOnRender)
  }

  onRender() {
    const main = document.querySelector("[data-workspace-kind]")
    if (!main) {
      // Left the settings hub — reset so a future re-entry announces.
      this.lastKind = null
      return
    }

    const kind = main.dataset.workspaceKind

    // Only announce on actual transitions. First load is silent;
    // same-kind navigation is silent; cross-kind navigation announces.
    if (this.lastKind && this.lastKind !== kind) {
      const template = this[`${kind}Value`]
      if (template) {
        this.element.textContent = ""
        requestAnimationFrame(() => { this.element.textContent = template })
      }
    }

    this.lastKind = kind
  }
}

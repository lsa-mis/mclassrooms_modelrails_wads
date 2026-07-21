import { Controller } from "@hotwired/stimulus"

// Dismisses the REOPENED cookie-preferences panel (manage mode) without saving:
// discards any unsaved checkbox toggles and reverts to the consented-and-hidden
// state. The gem's controller exposes no public close action — its reopen()
// inverse (#hideBanner + #showManageLink) is private — so this reproduces that
// pair via the DOM.
//
// This controller is attached to the Cancel button, which the banner renders
// only when consent has already been given. So first-visit consent never gets a
// dismiss path (Escape included) and still requires an explicit accept/reject.
export default class extends Controller {
  connect() {
    this.onKeydown = this.onKeydown.bind(this)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  onKeydown(event) {
    if (event.key === "Escape") this.dismiss()
  }

  dismiss() {
    const root = this.element.closest("[data-controller~='biscuit']")
    if (!root) return

    const banner = root.querySelector("[data-biscuit-target='banner']")
    // Only act while the panel is actually open (guards the always-on Escape
    // listener — a no-op when the banner is already hidden).
    if (!banner || banner.hidden) return

    // Discard unsaved toggles: restore each checkbox to its server-rendered
    // (saved) value, so a later reopen doesn't show stale state.
    root
      .querySelectorAll("[data-biscuit-target='categoryCheckbox']")
      .forEach((checkbox) => { checkbox.checked = checkbox.defaultChecked })

    // Revert to consented-and-hidden (no consent POST — consent is unchanged).
    banner.hidden = true
    banner.setAttribute("aria-hidden", "true")

    const manageLink = root.querySelector("[data-biscuit-target='manageLink']")
    if (manageLink) manageLink.hidden = false
  }
}

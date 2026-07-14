import { Controller } from "@hotwired/stimulus"

// Footer controller. Two responsibilities:
// - dispatch a click to Biscuit's hidden manage-link so our footer button
//   can reopen the cookie preferences panel
// - sync the category checkboxes to the saved consent cookie first. Biscuit
//   renders them server-side at page load and never re-syncs client-side:
//   clicking "Accept all"/"Reject all" updates the cookie but never touches
//   the (still-in-DOM, just-hidden) checkboxes, so reopening to reconsider
//   granular choices after an all-or-nothing decision shows stale state
//   (e.g. all unchecked) until a full reload.
export default class extends Controller {
  reopenCookies(event) {
    event.preventDefault()
    this.#syncCheckboxesFromCookie()
    document.querySelector(".biscuit-manage-link")?.click()
  }

  #syncCheckboxesFromCookie() {
    const consent = this.#readConsentCookie()
    if (!consent) return

    document.querySelectorAll("[data-biscuit-target='categoryCheckbox']").forEach((checkbox) => {
      checkbox.checked = !!consent.categories?.[checkbox.dataset.category]
    })
  }

  // Hardcodes the cookie name "biscuit_consent" — matches
  // config/initializers/biscuit.rb's config.cookie_name. Update both
  // together if that's ever changed.
  #readConsentCookie() {
    const match = document.cookie.match(/(?:^|; )biscuit_consent=([^;]*)/)
    if (!match) return null

    try {
      return JSON.parse(decodeURIComponent(match[1]))
    } catch {
      return null
    }
  }
}

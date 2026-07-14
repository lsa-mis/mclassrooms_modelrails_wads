import { Controller } from "@hotwired/stimulus"

// Footer controller: reopens Biscuit's cookie preferences panel via its hidden
// manage-link. Biscuit renders the panel's category checkboxes server-side at
// page load and never re-syncs them client-side, so after you save a choice the
// reopened panel shows the STALE page-load state until a full reload. Before
// reopening, we read the biscuit_consent cookie (httponly:false by design, so
// it's JS-readable) and set each checkbox to your actual saved value.
export default class extends Controller {
  reopenCookies(event) {
    event.preventDefault()
    this.#syncPreferencesFromCookie()
    document.querySelector(".biscuit-manage-link")?.click()
  }

  #syncPreferencesFromCookie() {
    const raw = document.cookie.match(/(?:^|; )biscuit_consent=([^;]*)/)?.[1]
    if (!raw) return

    let categories
    try {
      categories = JSON.parse(decodeURIComponent(raw)).categories
    } catch {
      return
    }
    if (!categories) return

    document.querySelectorAll("[data-biscuit-target='categoryCheckbox']").forEach((checkbox) => {
      if (checkbox.dataset.category in categories) {
        checkbox.checked = Boolean(categories[checkbox.dataset.category])
      }
    })
  }
}

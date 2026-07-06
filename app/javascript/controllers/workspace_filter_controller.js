import { Controller } from "@hotwired/stimulus"

// Client-side name filter for the workspaces index "Other workspaces" list.
// The list is a user's own memberships (small N, rendered in full), so an
// instant in-page filter beats a server round-trip + pagination. Hides
// non-matching rows, announces the visible count via a polite live region,
// and reveals an empty-state message when nothing matches.
//
// No connect() pre-filter: the server renders the full list + empty status,
// which is the correct initial state, and it avoids the live region
// announcing a count on page load.
export default class extends Controller {
  static targets = ["input", "item", "status", "empty"]
  static values = { statusTemplate: String }

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase()
    let visible = 0

    this.itemTargets.forEach((item) => {
      const matches = query === "" || (item.dataset.name || "").includes(query)
      item.hidden = !matches
      if (matches) visible += 1
    })

    if (this.hasStatusTarget) {
      this.statusTarget.textContent = this.statusTemplateValue.replace("__COUNT__", visible)
    }
    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = visible > 0
    }
  }
}

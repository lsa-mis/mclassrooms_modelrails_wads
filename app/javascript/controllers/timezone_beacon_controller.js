import { Controller } from "@hotwired/stimulus"

// Sends the browser's IANA timezone (Intl reads the OS clock, so VPN-immune); the server keeps it only when unset.
// Best-effort: a failed request is silent, and the preferences page still sets the timezone by hand.
export default class extends Controller {
  static values = { url: String }

  async connect() {
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone
    if (!tz) return

    try {
      await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json"
        },
        body: JSON.stringify({ timezone: tz })
      })
    } catch (_e) {
      // Best-effort; silent failure is correct here.
    }
  }
}

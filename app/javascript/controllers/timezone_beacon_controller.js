import { Controller } from "@hotwired/stimulus"

// Fires once per layout connect on authenticated pages. Reads the
// browser-detected IANA timezone via Intl.DateTimeFormat (which is
// VPN-immune because it reads the OS-level clock setting, not geo-IP),
// PATCHes it to the timezone endpoint. The server-side contract is
// idempotent: writes only when timezone is currently nil, so this
// never clobbers an explicit user choice.
//
// Failures are silent — the beacon is best-effort. If the request fails
// (network blip, server error, CSP rejection), the user can still set
// their timezone manually from the preferences page.
export default class extends Controller {
  static values = { url: String, token: String }

  async connect() {
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone
    if (!tz) return

    try {
      await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.tokenValue,
          "Accept": "application/json"
        },
        body: JSON.stringify({ timezone: tz })
      })
    } catch (_e) {
      // Best-effort; silent failure is correct here.
    }
  }
}

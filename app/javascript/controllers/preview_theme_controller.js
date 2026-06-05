import { Controller } from "@hotwired/stimulus"

// Dev-only light/dark toggle for the component preview host (Lookbook + the
// ViewComponent preview controller). Flips `.dark` on <html> and remembers the
// choice in a `preview_theme` cookie.
//
// Intentionally self-contained: it does NOT reuse the app's real theme system,
// which is auth/route/icon-coupled and deliberately absent from the minimal
// preview host (so axe audits scope cleanly to the component under test).
export default class extends Controller {
  static targets = ["label"]

  connect() {
    const cookie = document.cookie.match(/(?:^|; )preview_theme=(\w+)/)
    this.dark = cookie
      ? cookie[1] === "dark"
      : window.matchMedia("(prefers-color-scheme: dark)").matches
    this.#apply()
  }

  toggle() {
    this.dark = !this.dark
    document.cookie = `preview_theme=${this.dark ? "dark" : "light"};path=/;max-age=31536000;SameSite=Lax`
    this.#apply()
  }

  #apply() {
    document.documentElement.classList.toggle("dark", this.dark)
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = this.dark ? "Dark" : "Light"
    }
  }
}

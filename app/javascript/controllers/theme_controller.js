import { Controller } from "@hotwired/stimulus"

// Resolution lives in shared/_theme_script, which must run before first paint (#624).
export default class extends Controller {
  static values = { theme: { type: String, default: "system" } }

  connect() {
    this.applyTheme()
    this.mediaQuery = window.ModelRails.darkMediaQuery
    this.boundApplyTheme = this.applyTheme.bind(this)
    this.mediaQuery.addEventListener("change", this.boundApplyTheme)
  }

  disconnect() {
    this.mediaQuery?.removeEventListener("change", this.boundApplyTheme)
  }

  themeValueChanged() {
    this.applyTheme()
  }

  applyTheme() {
    document.documentElement.classList.toggle("dark", window.ModelRails.themeIsDark(this.themeValue))
  }
}

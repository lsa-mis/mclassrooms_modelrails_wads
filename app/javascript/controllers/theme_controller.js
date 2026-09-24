import { Controller } from "@hotwired/stimulus"

// Theme resolution is NOT defined here. `shared/_theme_script` owns it, because
// that script has to run before first paint and therefore cannot import this
// module — so a copy here would be a second answer to the same question, free
// to drift for exactly the window before Stimulus boots (#624). This reads the
// shared definition instead, and the media query list with it.
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

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { theme: { type: String, default: "system" } }

  connect() {
    this.applyTheme()
    this.mediaQuery = window.matchMedia("(prefers-color-scheme: dark)")
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
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
    const isDark = this.themeValue === "dark" || (this.themeValue === "system" && prefersDark)

    document.documentElement.classList.toggle("dark", isDark)
  }
}

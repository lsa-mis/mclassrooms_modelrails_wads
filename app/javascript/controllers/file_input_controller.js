import { Controller } from "@hotwired/stimulus"

// Shows WHICH files a file input has selected — the native control only shows a count
// ("3 files"). On change: one pill per file into the list (cloned from the <template>),
// and the selection mirrored into the always-present sr-only status live region.
// INVARIANT: file names are written via textContent, never innerHTML — names are
// user-controlled. The one/many/none values are host-supplied strings with
// %{count}/%{names} placeholders.
export default class extends Controller {
  static targets = ["input", "list", "pill", "status"]
  static values = { one: String, many: String, none: String }

  update() {
    const files = Array.from(this.inputTarget.files)
    this.listTarget.replaceChildren(...files.map((file) => this.#pill(file.name)))
    this.listTarget.hidden = files.length === 0
    this.statusTarget.textContent = this.#announcement(files)
  }

  #pill(name) {
    const pill = this.pillTarget.content.firstElementChild.cloneNode(true)
    pill.textContent = name
    return pill
  }

  #announcement(files) {
    if (files.length === 0) return this.noneValue
    const template = files.length === 1 ? this.oneValue : this.manyValue
    return template
      .replaceAll("%{count}", String(files.length))
      .replaceAll("%{names}", files.map((file) => file.name).join(", "))
  }
}

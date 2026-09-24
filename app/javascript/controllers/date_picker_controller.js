import { Controller } from "@hotwired/stimulus"
import * as topLayer from "overlays/top_layer"

// Month names for the `long` format, taken from the browser's own locale data so
// a typed "September 3, 2026" parses without shipping a table.
const MONTH_NAMES = Array.from({ length: 12 }, (_, i) =>
  new Date(2000, i, 1).toLocaleDateString("default", { month: "long" }).toLowerCase()
)

export default class extends Controller {
  static targets = ["trigger", "popover", "hidden", "input", "error"]
  static values = { invalidMessage: String, rangeMessage: String }

  connect() {
    this.#outsideHandler = (e) => {
      if (!this.element.contains(e.target)) this.close()
    }
  }

  disconnect() {
    document.removeEventListener("click", this.#outsideHandler)
  }

  toggle() {
    this.isOpen ? this.close() : this.open()
  }

  open() {
    // No-op unless the panel is anchor-positioned (`position: fixed`); top_layer.js
    // refuses anything still on the pre-Baseline `absolute` fallback.
    this.popoverTarget.dataset.open = "true"
    topLayer.enable(this.popoverTarget)
    topLayer.show(this.popoverTarget)
    this.triggerTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.#outsideHandler)
    this.isOpen = true
  }

  close() {
    topLayer.hide(this.popoverTarget)
    topLayer.disable(this.popoverTarget)
    this.popoverTarget.dataset.open = "false"
    this.triggerTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.#outsideHandler)
    this.isOpen = false
  }

  // Escape inside the popover (or any explicit dismissal) closes AND returns focus to
  // the trigger so keyboard users are never stranded in a hidden subtree (APG dialog).
  closeAndFocus(event) {
    if (event) event.preventDefault()
    this.close()
    this.triggerTarget.focus()
  }

  // Escape on the trigger while open closes the popover in place.
  triggerKeydown(event) {
    if (event.key === "Escape" && this.isOpen) {
      event.preventDefault()
      this.close()
    }
  }

  // --- the typed path ------------------------------------------------------

  // Enter commits without submitting the surrounding form: a date field inside a
  // filter form should apply the date, not send the form on the first Enter.
  commitOnEnter(event) {
    if (event.key !== "Enter") return
    event.preventDefault()
    this.commit()
  }

  // Parse, bound-check, then write back. Three outcomes and each is explicit:
  // empty clears, a good date is stored AND normalised into the box, and a bad one
  // leaves the text alone for correction while changing nothing that was stored —
  // silently reverting someone's typing is how a field loses trust.
  commit() {
    const raw = this.inputTarget.value.trim()

    if (raw === "") {
      this.#setHidden("")
      this.#clearError()
      return
    }

    const date = this.#parse(raw)
    if (!date) return this.#showError(this.invalidMessageValue)
    if (!this.#withinBounds(date)) return this.#showError(this.rangeMessageValue)

    const iso = this.#iso(date)
    this.#setHidden(iso)
    this.inputTarget.value = this.#format(date)
    this.#clearError()
  }

  dateSelected(event) {
    const iso = event.detail.date
    const [year, month, day] = iso.split("-").map(Number)

    this.#setHidden(iso)
    if (this.hasInputTarget) this.inputTarget.value = this.#format(new Date(year, month - 1, day))
    this.#clearError()
    this.closeAndFocus()
  }

  // --- internals -----------------------------------------------------------

  // Tried in order, and ISO is always accepted whatever `format:` says: it is
  // unambiguous and it is what the hidden input already stores, so a value copied
  // out of the DOM can be pasted back in.
  #parse(raw) {
    const iso = raw.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/)
    if (iso) return this.#build(+iso[1], +iso[2], +iso[3])

    const slashed = raw.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/)
    if (slashed) return this.#build(+slashed[3], +slashed[1], +slashed[2])

    const long = raw.match(/^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})$/)
    if (long) {
      const month = MONTH_NAMES.indexOf(long[1].toLowerCase())
      if (month >= 0) return this.#build(+long[3], month + 1, +long[2])
    }

    return null
  }

  // Rejects a well-shaped date that does not exist: "2026-02-31" parses as three
  // numbers and would otherwise roll forward into March without complaint.
  #build(year, month, day) {
    const date = new Date(year, month - 1, day)
    const real = date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day
    return real ? date : null
  }

  #withinBounds(date) {
    const iso = this.#iso(date)
    const { datePickerMin: min, datePickerMax: max } = this.inputTarget.dataset
    if (min && iso < min) return false
    if (max && iso > max) return false
    return true
  }

  // Local parts, never toISOString(): that converts to UTC, which shifts the date
  // by a day for anyone west of Greenwich.
  #iso(date) {
    const pad = (n) => String(n).padStart(2, "0")
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
  }

  #format(date) {
    switch (this.inputTarget.dataset.datePickerFormat) {
      case "iso":
        return this.#iso(date)
      case "short":
        return `${date.getMonth() + 1}/${date.getDate()}/${date.getFullYear()}`
      default:
        return date.toLocaleDateString("default", { month: "long", day: "numeric", year: "numeric" })
    }
  }

  #setHidden(iso) {
    if (this.hasHiddenTarget) this.hiddenTarget.value = iso
  }

  #showError(message) {
    this.inputTarget.setAttribute("aria-invalid", "true")
    if (this.hasErrorTarget) this.errorTarget.textContent = message
  }

  #clearError() {
    this.inputTarget.setAttribute("aria-invalid", "false")
    if (this.hasErrorTarget) this.errorTarget.textContent = ""
  }

  #outsideHandler = null
  isOpen = false
}

import { Controller } from "@hotwired/stimulus"

// Debounced auto-submit for the Find a Room filter form (MiClassrooms Phase 3
// Task 5, Brief §5.2). Distinct from `search_form_controller` (used by the
// workspace members filter bar) and the template's `auto_submit_controller`
// (plain, no debounce): text inputs (building/room name) fire on every
// keystroke, so `submit()` debounces to avoid a request per character —
// selects/checkboxes are a single deliberate choice, so `submitNow()` fires
// immediately.
//
// `requestSubmit()` walks the standard HTMLFormElement submit path, so the
// form's GET method + `data-turbo-frame`/`data-turbo-action` targeting (set
// on the <form> itself) are preserved — this controller only decides WHEN to
// submit, never how.
// Redesign (2026-07 sprint): the controller now attaches to a WRAPPER around
// the form AND the results frame (not the <form> itself), with the form as a
// target — so controls living inside the re-rendering frame (the sort select,
// via its `form=` attribute) can still fire filter-form actions after every
// Turbo re-render without re-wiring.
export default class extends Controller {
  static targets = ["form"]
  static values = { delay: { type: Number, default: 300 } }

  submit() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.form.requestSubmit(), this.delayValue)
  }

  submitNow() {
    clearTimeout(this.timeout)
    this.form.requestSubmit()
  }

  frameRendered() {
    this.restoreFocus()
    this.announceResults()
    this.syncPanelCount()
  }

  // Panel review (Léonie): a frame swap destroys the activated element and
  // Turbo drops focus to <body>. After the reset-links became full visits,
  // the only in-frame control left is the sort select (wired to the form via
  // `form=`), so when a render leaves focus on <body>, return it there. A
  // debounced text-input submit never trips this — focus stays in the form.
  restoreFocus() {
    if (document.activeElement !== document.body) return

    this.element.querySelector("#filter_sort")?.focus()
  }

  // Pre-release audit (Léonie): a live region that is itself replaced by the
  // frame swap is not reliably announced by screen readers. The persistent
  // #results_announcer lives OUTSIDE the frame; copy the fresh count into it
  // after each render so filtering is never silent to AT.
  announceResults() {
    const announcer = document.getElementById("results_announcer")
    const count = this.element.querySelector("[data-results-count]")
    if (announcer && count) announcer.textContent = count.textContent.trim()
  }

  // The applied-count badge sits on the More-filters summary, OUTSIDE the
  // results frame, so a frame-only re-render leaves it stale (backlog #7).
  // The frame carries a hidden [data-panel-count] mirror of the same
  // server-side count — copy it into the badge after each render, so the
  // server stays the single source of truth for the count AND its localized
  // phrasing (same relay pattern as announceResults above).
  syncPanelCount() {
    const mirror = this.element.querySelector("[data-panel-count]")
    const holder = this.element.querySelector("[data-panel-badge]")
    if (!mirror || !holder) return

    const text = mirror.textContent.trim()
    holder.hidden = text === ""
    if (text && holder.firstElementChild) holder.firstElementChild.textContent = text
  }

  get form() {
    return this.hasFormTarget ? this.formTarget : this.element
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}

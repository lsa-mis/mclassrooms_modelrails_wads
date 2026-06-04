import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["body", "search", "pageLabel", "sortIndicator", "status"]
  static values = {
    perPage: { type: Number, default: 10 },
    total:   { type: Number, default: 0 }
  }

  connect() {
    this.#allRows = Array.from(this.bodyTarget.querySelectorAll("tr[data-data-table-row]"))
    this.#filtered = [...this.#allRows]
    this.#page = 1
    this.#sortKey = null
    this.#sortDir = null
    this.#render()
  }

  filter() {
    const q = this.searchTarget.value.trim().toLowerCase()
    this.#filtered = q
      ? this.#allRows.filter(row =>
          row.textContent.toLowerCase().includes(q)
        )
      : [...this.#allRows]
    this.#page = 1
    this.#sortKey = null
    this.#sortDir = null
    this.#clearSortIndicators()
    this.#clearAriaSort()
    this.#render()
  }

  sort({ params: { key } }) {
    if (this.#sortKey === key) {
      this.#sortDir = this.#sortDir === "asc" ? "desc" : null
      if (!this.#sortDir) this.#sortKey = null
    } else {
      this.#sortKey = key
      this.#sortDir = "asc"
    }

    this.#clearSortIndicators()
    if (this.#sortKey) {
      const indicator = this.sortIndicatorTargets.find(
        el => el.dataset.dataTableSortKey === this.#sortKey &&
              el.dataset.dataTableDir === this.#sortDir
      )
      if (indicator) indicator.dataset.active = this.#sortDir
    }

    // Reflect the active sort to assistive tech: the owning th gets
    // aria-sort=ascending|descending, every other sortable th resets to none.
    this.#updateAriaSort()

    if (this.#sortKey) {
      const colIdx = this.#columnIndex(this.#sortKey)
      this.#filtered.sort((a, b) => {
        const av = a.cells[colIdx]?.textContent.trim() ?? ""
        const bv = b.cells[colIdx]?.textContent.trim() ?? ""
        const n = parseFloat(av) - parseFloat(bv)
        const cmp = isNaN(n) ? av.localeCompare(bv) : n
        return this.#sortDir === "asc" ? cmp : -cmp
      })
    }

    this.#page = 1
    this.#render()
  }

  prevPage() {
    if (this.#page > 1) { this.#page--; this.#render() }
  }

  nextPage() {
    if (this.#page < this.#totalPages) { this.#page++; this.#render() }
  }

  #render() {
    const rows = this.#filtered
    const perPage = this.perPageValue
    const total = rows.length

    const start = perPage > 0 ? (this.#page - 1) * perPage : 0
    const end   = perPage > 0 ? start + perPage : total

    this.#allRows.forEach(row => { row.style.display = "none" })
    // Re-insert the filtered rows in SORTED order so the DOM matches the sort.
    // The previous display-only approach left the tbody in its original order,
    // so aria-sort announced an order the visible rows did not actually have
    // (a WCAG false state) and sort was a visible no-op on a single page.
    // appendChild MOVES each node, so iterating the sorted array reorders the
    // tbody; filtered-out rows stay hidden and their position is irrelevant.
    rows.forEach(row => this.bodyTarget.appendChild(row))
    rows.slice(start, end).forEach(row => { row.style.display = "" })

    if (this.hasPageLabelTarget) {
      this.pageLabelTarget.textContent =
        perPage > 0 && total > 0
          ? this.#interpolate(this.#pageTemplate, {
              page: this.#page, pages: this.#totalPages, rows: total
            })
          : this.#interpolate(this.#resultsTemplate, { count: total })
    }

    // Announce the result count to screen readers (filter/sort/page outcome).
    if (this.hasStatusTarget) {
      this.statusTarget.textContent =
        this.#interpolate(this.#resultsTemplate, { count: total })
    }
  }

  #clearSortIndicators() {
    this.sortIndicatorTargets.forEach(el => delete el.dataset.active)
  }

  #updateAriaSort() {
    this.#sortableHeaders().forEach(th => {
      const key = th.querySelector("[data-data-table-key-param]")?.dataset.dataTableKeyParam
      th.setAttribute(
        "aria-sort",
        this.#sortKey && key === this.#sortKey
          ? (this.#sortDir === "asc" ? "ascending" : "descending")
          : "none"
      )
    })
  }

  #clearAriaSort() {
    this.#sortableHeaders().forEach(th => th.setAttribute("aria-sort", "none"))
  }

  #sortableHeaders() {
    return Array.from(this.element.querySelectorAll("th[aria-sort]"))
  }

  // Index among ALL header cells (not just sortable ones) so the cell offset
  // is correct even when non-sortable columns precede the sorted one.
  #columnIndex(key) {
    const headers = Array.from(this.element.querySelectorAll("thead th"))
    return headers.findIndex(
      th => th.querySelector("[data-data-table-key-param]")?.dataset.dataTableKeyParam === key
    )
  }

  // Plain %{name} substitution matching the I18n template strings passed from
  // the component (data-data-table-*-template attributes on the root).
  #interpolate(template, vars) {
    return (template || "").replace(/%\{(\w+)\}/g, (_, name) =>
      name in vars ? vars[name] : `%{${name}}`
    )
  }

  get #resultsTemplate() {
    return this.element.dataset.dataTableResultsTemplate ?? ""
  }

  get #pageTemplate() {
    return this.element.dataset.dataTablePageTemplate ?? ""
  }

  get #totalPages() {
    return this.perPageValue > 0
      ? Math.max(1, Math.ceil(this.#filtered.length / this.perPageValue))
      : 1
  }

  #allRows = []
  #filtered = []
  #page = 1
  #sortKey = null
  #sortDir = null
}

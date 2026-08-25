// Keyboard movement shared by the menu family.
//
// Two algorithms were duplicated across four controllers, and one bug had to be
// fixed in three of the copies before it was — the ArrowUp entry correction
// reached menu and combobox but not command. Both are pure movement: they answer
// "which item is next", and never touch focus, aria, or DOM. Each controller keeps
// its own focus mechanics, which is where the four genuinely differ.
//
// Deliberately NOT here: menubar's ←/→ bar navigation. It coordinates co-indexed
// itemTargets and menuOutlets, so it cannot be engine configuration.

// Type-ahead buffer with the APG idle reset. Holds only the buffer; the caller
// owns the item collection and how a match gets focused.
export class TypeAhead {
  constructor(resetAfter = 1000) {
    this.buffer = ""
    this.resetAfter = resetAfter
    this._timer = null
  }

  push(char) {
    this.buffer += char.toLowerCase()
    if (this._timer) clearTimeout(this._timer)
    this._timer = setTimeout(() => { this.buffer = "" }, this.resetAfter)
    return this.buffer
  }

  // Controllers clear the idle timer on disconnect; a live timeout would fire into
  // a torn-down controller.
  cancel() {
    if (this._timer) clearTimeout(this._timer)
    this._timer = null
    this.buffer = ""
  }

  // Index of the next item whose text starts with the buffer, scanning forward
  // from `from` and wrapping; -1 when nothing matches.
  //
  // `skip` exists because the two callers filter differently and both shapes must
  // survive: menu pre-filters into enabledItems and passes no skip, while menubar
  // scans itemTargets unfiltered — its indices are co-indexed with menuOutlets, so
  // it cannot filter first — and skips inline.
  match(items, from, {skip = null} = {}) {
    for (let n = 1; n <= items.length; n++) {
      const i = (from + n) % items.length
      const item = items[i]
      if (skip && skip(item)) continue
      if (item.textContent.trim().toLowerCase().startsWith(this.buffer)) return i
    }
    return -1
  }
}

// Next active option for an aria-activedescendant listbox, given the visible set
// and the index of the current one (-1 when none is active). Returns null for keys
// that do not move.
//
// The ArrowUp branch is the one that shipped wrong: with nothing active, the
// modulo alone lands one short of the last option. APG says enter at the END.
export function nextActive(items, current, key) {
  if (!items.length) return null

  switch (key) {
    case "ArrowDown":
      return items[(current + 1) % items.length]
    case "ArrowUp":
      return current === -1 ? items[items.length - 1] : items[(current - 1 + items.length) % items.length]
    case "Home":
      return items[0]
    case "End":
      return items[items.length - 1]
    default:
      return null
  }
}

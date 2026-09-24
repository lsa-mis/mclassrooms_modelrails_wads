// Post-navigation focus management (WCAG 2.4.3, #424). A Turbo Drive visit
// replaces the document under the user; without this, a keyboard or
// screen-reader user's focus and virtual cursor stay parked where the OLD
// page's element used to be. Every layout renders `#main-content` with
// tabindex="-1" as the landing target — this handler is the missing half
// that actually moves focus there.
//
// Deliberately NOT covered:
// - initial page load (no `turbo:visit` has fired; the browser's default
//   focus is correct)
// - restoration visits (back/forward — the browser restores scroll and
//   context; yanking focus would fight it)
// - destinations that focus something themselves (an autofocused field wins;
//   we only claim focus when it is still parked on <body>)
let pendingNavigationFocus = false

document.addEventListener("turbo:visit", (event) => {
  if (event.detail?.action !== "restore") pendingNavigationFocus = true
})

document.addEventListener("turbo:load", () => {
  if (!pendingNavigationFocus) return
  pendingNavigationFocus = false

  const parked = document.activeElement === document.body || document.activeElement === null
  if (!parked) return

  // A same-URL redirect on a morphing page renders through Turbo's
  // MorphingPageRenderer, whose shouldAutofocus is false — so the response's
  // autofocus never fires and focus reaches here still parked (#1036). Honour it
  // before the landmark: the destination did nominate a focus target, which is
  // exactly the "destinations that focus something themselves" case above. On a
  // non-morph render Turbo's own autofocus has already run and focus is not
  // parked, so this never fires there.
  // Same filter as Turbo's own queryAutofocusableElement, so the morph path picks the
  // element the non-morph path would have picked: the first [autofocus] that is not
  // inert, disabled, hidden, or inside a closed details/dialog.
  const autofocused = Array.from(document.querySelectorAll("[autofocus]")).find((el) =>
    el.closest("[inert], :disabled, [hidden], details:not([open]), dialog:not([open])") === null &&
    typeof el.focus === "function")
  if (autofocused) {
    autofocused.focus({ preventScroll: true })
    if (document.activeElement === autofocused) return
  }

  const target = document.getElementById("main-content")
  // preventScroll: a fresh navigation already renders at the top, and the
  // default focus scroll nudges content under the sticky header on small
  // viewports (surfaced as a transparent-over-media audit failure).
  if (target) target.focus({ preventScroll: true })
})

// Focus return for controls that must navigate the whole page (a sort, a page
// size, a pager link, a date-range preset, a pivot into the search box). A
// frame swap keeps focus on the control that changed; a full visit cannot, and
// landing on #main-content after every sort cost a keyboard user the walk back
// to the header (WCAG 2.4.3). The control carries — or sits inside an element
// carrying — data-focus-key, naming the element to land on in the NEW
// document. The key is remembered at click time and applied at
// turbo:before-render as an `autofocus` on the new body, so Turbo's own
// autofocus contract (and the fallback above) does the focusing: one move, one
// announcement. Inside a keyed container the target is whichever child is now
// aria-current (the page size just chosen, the pager's current page) or,
// failing that, its first focusable descendant; a bare container gets
// tabindex="-1" so it can take focus at all.
const FOCUSABLE = "a[href], button:not([disabled]), input:not([type=hidden]):not([disabled]), select, textarea, [tabindex]"
let pendingFocusKey = null

document.addEventListener("click", (event) => {
  const keyed = event.target.closest?.("[data-focus-key]")
  pendingFocusKey = keyed ? keyed.dataset.focusKey : null
})

document.addEventListener("turbo:before-render", (event) => {
  // The cached preview renders first and the real response after it; the key
  // is spent on the real one.
  if (!pendingFocusKey || event.detail.isPreview) return
  const key = pendingFocusKey
  pendingFocusKey = null

  const keyed = event.detail.newBody.querySelector(`[data-focus-key="${CSS.escape(key)}"]`)
  if (!keyed) return
  const target = keyed.matches("[aria-current]") || keyed.matches(FOCUSABLE)
    ? keyed
    : keyed.querySelector("[aria-current]") || keyed.querySelector(FOCUSABLE) || keyed
  if (!target.matches(FOCUSABLE)) target.setAttribute("tabindex", "-1")
  target.setAttribute("autofocus", "")
})

document.addEventListener("turbo:load", () => { pendingFocusKey = null })

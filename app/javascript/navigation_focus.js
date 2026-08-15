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

  const target = document.getElementById("main-content")
  const parked = document.activeElement === document.body || document.activeElement === null
  // preventScroll: a fresh navigation already renders at the top, and the
  // default focus scroll nudges content under the sticky header on small
  // viewports (surfaced as a transparent-over-media audit failure).
  if (target && parked) target.focus({ preventScroll: true })
})

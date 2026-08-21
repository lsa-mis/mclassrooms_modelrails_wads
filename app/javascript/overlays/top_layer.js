// Promotes a floating panel into the browser's top layer.
//
// `position: absolute`/`fixed` escapes overflow clipping but never a *stacking
// context*: a panel's `z-50` is scoped to the nearest positioned ancestor with a
// z-index, so a `sticky z-40` header (app/views/shared/_header.html.erb) or a
// `backdrop-blur` navbar (UI::NavbarComponent) buries it. No z-index fixes that
// from the inside.
//
// `showPopover()` paints the element above every stacking context while leaving it
// in the DOM — which is what makes it usable here: moving the panel would unbind
// the Stimulus actions inside it, and `absolute` positioning keeps resolving
// against the trigger's wrapper because the top layer changes paint order only.
//
// `manual` rather than `auto`: `auto` brings its own light-dismiss and its own
// nesting stack, which would fight the layer stack in dismiss.js.

export const SUPPORTED =
  typeof HTMLElement !== "undefined" && Object.hasOwn(HTMLElement.prototype, "popover")

// Browsers without the Popover API keep the current behaviour — still positioned,
// still correct in the common case, just vulnerable to a stacking context above it.
const usable = (element) => SUPPORTED && !!element

// The top layer re-parents an element's containing block to the viewport, so anything
// placed relative to a DOM ancestor (`position: absolute` + `top-full`) is torn off its
// trigger — measured 1320px adrift on the pre-Baseline `absolute` fallback that Firefox
// and Safari still take. `position: fixed` is already viewport-relative, so for those the
// change is a no-op. Gate on that invariant rather than on a feature name: it stays
// correct whatever a browser supports, and the ungated case simply keeps today's
// behaviour (correctly placed, still buriable) instead of flying off-screen.
const viewportPositioned = (element) => getComputedStyle(element).position === "fixed"

// data-top-layer is the hook for the UA-default reset in application.css.
export function enable(element) {
  if (!usable(element) || !viewportPositioned(element)) return false

  element.popover = "manual"
  element.dataset.topLayer = ""
  return true
}

export function show(element) {
  if (!usable(element) || !element.popover) return false

  try { element.showPopover() } catch { /* already showing, or not connected yet */ }
  return true
}

export function hide(element) {
  if (!usable(element) || !element.popover) return false

  try { element.hidePopover() } catch { /* already hidden */ }
  return true
}

// Hiding a popover does not put it back in the page's flow: the UA gives
// `[popover]` `position: fixed` open or closed. Callers that lay the page out
// around the element must disable it, not just hide it.
export function disable(element) {
  if (!usable(element)) return false

  element.removeAttribute("popover")
  delete element.dataset.topLayer
  return true
}

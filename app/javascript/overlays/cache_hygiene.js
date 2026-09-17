// Closes overlays before Turbo caches the page (#713).
//
// Turbo's snapshot clone normalises only `select`, `input[type=password]` and
// `noscript` (turbo-rails 2.0.23), so an overlay left open when the user navigates
// away is frozen open in the cached page and Back restores it. A menu comes back as
// a `role="menu"` with live menuitems — nothing hides it once `hidden` is gone, and
// `menu_controller#disconnect()` only cancels the type-ahead — under a trigger still
// reporting `aria-expanded="true"`, whose next click is dead because the controller
// reads `openValue` as true.
//
// A dialog comes back worse: open, `display: block`, matching `:modal`, still carrying
// the hardcoded `aria-modal="true"` from UI::DialogComponent — a named dialog claiming
// the rest of the page is not there — with Escape dead (`cancel` fires for modal
// dialogs only) and focus on <body>.
//
// The measured route is NOT Turbo's snapshot cache. On the Drive path this app wins by
// accident: Turbo defers `snapshot.clone()` one event-loop tick past this event, so
// `modal_controller#disconnect()` closes the dialog on the old body before the clone is
// taken. What the proving spec exercises is the other route — **the browser's
// back-forward cache**. Every navigation away that Turbo does not render itself leaves
// the live DOM exactly as it stood at unload, and Back restores that same document:
// an external link, `data-turbo="false"`, or any `data-turbo-track="reload"` mismatch
// (both stylesheet links carry it, so an asset-digest change alone is enough) makes
// Turbo invalidate and hand the navigation to the browser. `turbo:before-cache` has
// already fired by then, which is exactly why this listener is what makes the restored
// DOM correct — there is no snapshot involved to fix it later.
//
// A second, unmeasured reason the sweep is not optional: on the Drive path the clone
// race is only won while the destination's head merge settles in microtasks. A merge
// that must await a stylesheet load would let the clone win. Plausible, but this file
// does not claim it as measured — the spec's stylesheet stripping takes the
// invalidation path above, not the merge path.
//
// `dialog.close()` raw, not `modal_controller#close()`: the controller animates out
// behind a `setTimeout`, and a close that has not finished when the page is cached or
// unloaded is not in what comes back. (`modal_closer_controller.js` routes through the
// controller for the opposite reason — there the animation is the point.)
//
// The close set runs on the live DOM and must be synchronous — anything deferred misses
// the clone, and misses the unload entirely. All three parts of a menu's open state are
// reversed together or none: `hidden` on the panel, `aria-expanded` on the trigger, and
// the Stimulus value. The top layer is left alone on purpose: the `[data-top-layer]` reset in
// application.css does not restore `display`, so stripping `popover` without the
// `hidden` above would promote an unreachable panel into a visible menu under a
// trigger that reports closed. A cloned popover is closed anyway, so
// `[popover]:not(:popover-open)` keeps it out of the restored page regardless.
//
// Submenus are not closed here: that is `menu_controller#close()`'s job via
// `#closeSubmenus`, and `submenu` has its own open state and its own `topLayer` call.
// Deferred with the other `topLayer.enable` callers — see the #713 deferral list.
document.addEventListener("turbo:before-cache", () => {
  document.querySelectorAll("dialog[open]").forEach((dialog) => dialog.close())

  document.querySelectorAll('[data-controller~="menu"][data-menu-open-value="true"]')
    .forEach((root) => {
      root.setAttribute("data-menu-open-value", "false")
      root.querySelectorAll('[data-menu-target="menu"]').forEach((menu) => { menu.hidden = true })
      root.querySelectorAll('[data-menu-target="trigger"]')
        .forEach((trigger) => trigger.setAttribute("aria-expanded", "false"))
    })
})

import { Controller } from "@hotwired/stimulus"

// Lazily loads the vendored Pannellum library (pinned as "pannellum" in
// config/importmap.rb -> vendor/javascript/pannellum.js) only when the
// visitor opts in by clicking "Load 360° view" — no panorama motion (or
// WebGL/JS payload) ships on initial page load, which also satisfies
// prefers-reduced-motion by default: nothing animates until a deliberate
// click.
//
// pannellum.js is a plain (non-ESM) build: it sets `window.pannellum` as a
// side effect and has no `export`s, so `import("pannellum")` is used purely
// to execute it — the viewer factory is read off the global afterward.
export default class extends Controller {
  static targets = ["viewer", "overlay"]
  static values = { url: String, previewUrl: String, label: String }

  async load() {
    try {
      await import("pannellum")
    } catch (error) {
      console.error("[panorama] failed to load the pannellum library", error)
      return
    }

    // Hide the WHOLE overlay (button + hint), not just the button: the
    // overlay is an absolute inset-0 sibling painted OVER the viewer, so
    // leaving it in place swallows every drag/wheel/click — the booted
    // panorama looks alive but is completely inert (found 2026-07-13).
    this.overlayTarget.hidden = true
    this.viewerTarget.hidden = false

    this.viewer = window.pannellum.viewer(this.viewerTarget, {
      type: "equirectangular",
      panorama: this.urlValue,
      preview: this.previewUrlValue,
      autoLoad: true,
      compass: false
    })

    // The booted viewer container is the accessible control surface (it owns
    // its own keyboard/drag interaction model, which isn't native HTML
    // semantics) — role="application" + a descriptive label per the room.
    // Pannellum reuses THIS element as .pnlm-container and gives it
    // tabindex="0"; its keyboard model (arrows pan, +/- zoom) only works
    // while it has focus.
    this.viewerTarget.setAttribute("role", "application")
    this.viewerTarget.setAttribute("aria-label", this.labelValue)

    // Hiding the Load button dropped focus to <body> (WCAG 2.4.3): hand it
    // to the viewer so keyboard users land where the interaction lives.
    this.viewerTarget.focus()
  }

  disconnect() {
    this.viewer?.destroy()
    this.viewer = null
  }
}

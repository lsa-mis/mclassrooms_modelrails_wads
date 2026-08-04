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
  static targets = ["viewer", "overlay", "instructions"]
  // hfov MUST stay the bare constructor form `hfov: Number`. Any object
  // descriptor (`{ type: Number }`, with or without `default:`) makes
  // `hasHfovValue` true unconditionally, which silently defeats the
  // missing-attribute check in load().
  static values = { url: String, previewUrl: String, label: String, hfov: Number }

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

    // hfov comes from Panorama::Rectilinear::HFOV_DEG (emitted by ERB as
    // data-panorama-hfov-value), NOT from Pannellum's default. The pre-load
    // image is rendered at exactly this field of view, so a mismatch makes the
    // image jump on click — which reads as a UI glitch rather than as a bug.
    // Change it in Ruby, then re-render:
    //   bin/rails panoramas:render_flat FORCE=1
    //
    // ERB emits the attribute unconditionally, so the fallback is only
    // reachable when the ERB -> Stimulus binding has already been severed —
    // hence the console.error. It is otherwise silent and invisible:
    // HFOV_DEG, Pannellum's own internal default, and this fallback are all
    // 100 today, so a severed binding still boots at the "right" number.
    if (!this.hasHfovValue) {
      console.error(
        "[panorama] data-panorama-hfov-value is missing — the ERB -> Stimulus binding is severed. " +
        "Falling back to 100; the pre-load image may not match the viewer."
      )
    }
    const hfov = this.hasHfovValue ? this.hfovValue : 100

    this.viewer = window.pannellum.viewer(this.viewerTarget, {
      type: "equirectangular",
      panorama: this.urlValue,
      preview: this.previewUrlValue,
      hfov: hfov,
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

    // role="application" suppresses browse mode, and the overlay carrying the
    // pre-load hint was hidden a few lines up — so without this the user is
    // handed an arrow-key-driven canvas with no instructions and no stated
    // exit. The instructions element is a visually-hidden sibling OUTSIDE the
    // overlay (see _pano_pane.html.erb) precisely so it survives that hide.
    this.viewerTarget.setAttribute("aria-describedby", this.instructionsTarget.id)

    // Hiding the Load button dropped focus to <body> (WCAG 2.4.3): hand it
    // to the viewer so keyboard users land where the interaction lives.
    this.viewerTarget.focus()
  }

  disconnect() {
    this.viewer?.destroy()
    this.viewer = null
  }
}

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
  // hfov MUST stay the bare constructor form `hfov: Number` — never an
  // object descriptor (`hfov: { type: Number }` or similar), with or without
  // a `default:` key. Verified against the vendored stimulus.min.js:
  // `hasCustomDefaultValue()` is `void 0!==se(s)`, and `se` returns
  // `"object"` for any plain object descriptor — so ANY object form forces
  // `hasHfovValue` true unconditionally, default key present or not (see the
  // longer explanation in load() below). A bare `Number` with no attribute
  // present silently degrades to 0, and Pannellum CLAMPS (not rejects) hfov
  // to its minHfov of 50 rather than erroring — a viewer at double
  // magnification against a 100°-framed pre-load image, with no console
  // error to notice. The fallback below still closes that hole; it's just
  // not expressed here.
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

    // hfov comes from Panorama::Rectilinear::HFOV_DEG, NOT from Pannellum's
    // default. The static pre-load image is rendered at exactly this field of
    // view, so a mismatch here makes the image jump on click — which looks like
    // a UI glitch, not like a bug. Change it in Ruby, then re-render:
    //   bin/rails panoramas:render_flat FORCE=1
    //
    // The 100 fallback is applied HERE, manually, rather than as a Stimulus
    // `default:` on the value descriptor above — and the value descriptor
    // must stay the bare `hfov: Number`, never an object form. Tried an
    // object descriptor with a `default:` key first; reverted it after
    // finding Stimulus bakes `hasCustomDefaultValue` into `hasHfovValue`
    // (`this.data.has(attr) || hasCustomDefaultValue` — stimulus.min.js,
    // values blessing), where `hasCustomDefaultValue()` is
    // `void 0!==se(s)` and `se` returns `"object"` for ANY plain object
    // descriptor. So it isn't the `default:` key specifically — any object
    // form at all, `default:` or not, makes `hasHfovValue` return true
    // UNCONDITIONALLY, attribute present or not. That silently breaks the
    // diagnostic two lines down, which is the only thing that can tell "ERB
    // emitted the attribute and this controller read it" apart from "the
    // attribute name this controller reads no longer matches what ERB
    // emits, and the number came from thin air" — ERB's
    // data-panorama-hfov-value, Panorama::Rectilinear::HFOV_DEG, and
    // Pannellum's OWN internal default are all 100 today, so a severed
    // binding is invisible on the number alone. Keeping `hfov: Number` as
    // the bare constructor keeps hasHfovValue an honest raw-attribute check.
    // hasHfovValue is only false when the attribute is absent; a blank
    // attribute still makes it true (with hfovValue 0). ERB emits
    // Panorama::Rectilinear::HFOV_DEG unconditionally, so that case is
    // unreachable in practice — this fallback only ever fires on "attribute
    // absent" (a severed ERB -> Stimulus binding).
    const hfov = this.hasHfovValue ? this.hfovValue : 100

    this.viewer = window.pannellum.viewer(this.viewerTarget, {
      type: "equirectangular",
      panorama: this.urlValue,
      preview: this.previewUrlValue,
      hfov: hfov,
      autoLoad: true,
      compass: false
    })

    // Diagnostic, and the only thing pinning the ERB -> Stimulus
    // attribute-name binding (see the comment above): publishes whether the
    // camera that just booted came from the DOM attribute or the fallback,
    // so a renamed/severed value key surfaces as "default" in devtools
    // instead of silently rendering the numerically-identical 100.
    this.element.dataset.panoramaHfovSource = this.hasHfovValue ? "attribute" : "default"

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

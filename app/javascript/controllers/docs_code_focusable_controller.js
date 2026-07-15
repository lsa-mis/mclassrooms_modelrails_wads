import { Controller } from "@hotwired/stimulus"

// Makes horizontally-scrollable code blocks keyboard-focusable so keyboard-only
// users can scroll them (WCAG 2.1.1 / axe `scrollable-region-focusable`). The
// markdowndocs gem renders `<pre class="highlight">` WITHOUT a tabindex, but it
// DOES add tabindex="0" to scrollable tables (gem #30); this mirrors that
// behaviour for the code blocks the gem misses.
//
// Applied client-side because whether a block overflows depends on the viewport
// width (Cuprite's 1400px window overflows blocks that a narrower viewport did
// not). Our strict CSP (script-src :self with nonces, no unsafe-inline) rules
// out an inline script, so this rides a Stimulus controller on the docs content
// container — the same CSP-safe override pattern as docs_sidebar_controller.
export default class extends Controller {
  connect() {
    this.boundRefresh = this.refresh.bind(this)
    this.refresh()
    window.addEventListener("resize", this.boundRefresh)
  }

  disconnect() {
    window.removeEventListener("resize", this.boundRefresh)
  }

  refresh() {
    this.element.querySelectorAll("pre").forEach((pre) => {
      if (pre.scrollWidth > pre.clientWidth) {
        pre.setAttribute("tabindex", "0")
      }
    })
  }
}

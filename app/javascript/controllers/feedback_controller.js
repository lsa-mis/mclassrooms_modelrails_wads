import { Controller } from "@hotwired/stimulus"

// Opens the site-wide lsa_tdx_feedback modal from any in-page trigger (e.g. the
// /contact CTA). The gem's JS exposes window.LsaTdxFeedback globally and binds
// its own floating #lsa-tdx-feedback-trigger; this lets our own buttons open the
// same modal without duplicating that id. CSP-safe (Stimulus action, no inline
// handler).
export default class extends Controller {
  open(event) {
    event.preventDefault()
    window.LsaTdxFeedback?.showModal()
  }
}

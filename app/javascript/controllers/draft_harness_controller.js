import { Controller } from "@hotwired/stimulus"
import {
  serializeForm, validDraftShape, expired, draftKeyFor
} from "controllers/form_draft_controller"

// Test-harness bridge: exposes the form-draft pure helpers so system specs
// can exercise shape/expiry/serialization branches directly.
export default class extends Controller {
  connect() {
    window.formDraftHarness = { serializeForm, validDraftShape, expired, draftKeyFor }
  }
}

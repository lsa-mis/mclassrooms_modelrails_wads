import { Controller } from "@hotwired/stimulus"

// Drives passkey sign-in (authenticate) and registration (register).
// CSP-safe: no inline handlers. Endpoints are injected via Stimulus values.
// Full ceremony proven end-to-end in Task 11 (virtual authenticator).
export default class extends Controller {
  static values = {
    authOptionsUrl: String,
    authVerifyUrl:  String,
    regOptionsUrl:  String,
    regVerifyUrl:   String
  }
  static targets = ["status", "button", "nickname"]

  connect() {
    if (!this.#supported) {
      this.element.classList.add("passkeys-unsupported")
      if (this.hasButtonTarget) this.buttonTarget.hidden = true
      return
    }
    // Kick off conditional-UI (autofill) only on pages that supply auth URLs.
    // Register-only pages (settings, enrollment banner) omit authOptionsUrlValue
    // so they never create a spurious WebauthnChallenge row on page load.
    if (this.hasAuthOptionsUrlValue) this.#conditionalAuthenticate()
  }

  async authenticate() {
    if (!this.#supported) return
    this.#announce("")
    try {
      const options   = await this.#post(this.authOptionsUrlValue)
      const assertion = await navigator.credentials.get({
        publicKey: this.#decodeGetOptions(options)
      })
      const result = await this.#post(this.authVerifyUrlValue, this.#encodeAssertion(assertion))
      window.location = result.redirect_to
    } catch (e) {
      this.#handle(e)
    }
  }

  async register() {
    if (!this.#supported) return
    this.#announce("")
    const nickname = this.hasNicknameTarget ? this.nicknameTarget.value.trim() : ""
    try {
      const options     = await this.#post(this.regOptionsUrlValue)
      const credential  = await navigator.credentials.create({
        publicKey: this.#decodeCreateOptions(options)
      })
      const result = await this.#post(this.regVerifyUrlValue, {
        ...this.#encodeAttestation(credential),
        nickname
      })
      window.location = result.redirect_to
    } catch (e) {
      this.#handle(e)
    }
  }

  async #conditionalAuthenticate() {
    try {
      const available = await window.PublicKeyCredential
        ?.isConditionalMediationAvailable?.()
      if (!available) return

      const options   = await this.#post(this.authOptionsUrlValue)
      const assertion = await navigator.credentials.get({
        publicKey: this.#decodeGetOptions(options),
        mediation: "conditional"
      })
      const result = await this.#post(this.authVerifyUrlValue, this.#encodeAssertion(assertion))
      window.location = result.redirect_to
    } catch {
      // Conditional-UI cancellation is a normal user action — stay silent
    }
  }

  get #supported() {
    return window.isSecureContext && !!window.PublicKeyCredential
  }

  // POST with CSRF token; throws {body} on non-2xx
  async #post(url, body = null) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type":  "application/json",
        "Accept":        "application/json",
        ...(token && { "X-CSRF-Token": token })
      },
      ...(body !== null && { body: JSON.stringify(body) })
    })
    const data = await res.json()
    if (!res.ok) {
      // A gated factor endpoint asks us to re-authenticate first — navigate to
      // the interstitial rather than surfacing an error.
      if (res.status === 403 && data.reauth_required) {
        window.location = data.redirect_to
        return new Promise(() => {})
      }
      throw { body: data }
    }
    return data
  }

  #decodeGetOptions(opts) {
    const decoded = { ...opts }
    decoded.challenge = this.#b64ToBuffer(opts.challenge)
    if (opts.allowCredentials) {
      decoded.allowCredentials = opts.allowCredentials.map(c => ({
        ...c,
        id: this.#b64ToBuffer(c.id)
      }))
    }
    return decoded
  }

  #encodeAssertion(assertion) {
    return {
      id:    assertion.id,
      rawId: this.#bufferToB64(assertion.rawId),
      type:  assertion.type,
      response: {
        authenticatorData: this.#bufferToB64(assertion.response.authenticatorData),
        clientDataJSON:    this.#bufferToB64(assertion.response.clientDataJSON),
        signature:         this.#bufferToB64(assertion.response.signature),
        userHandle:        assertion.response.userHandle
          ? this.#bufferToB64(assertion.response.userHandle)
          : null
      }
    }
  }

  #decodeCreateOptions(opts) {
    const decoded = { ...opts }
    decoded.challenge = this.#b64ToBuffer(opts.challenge)
    decoded.user      = { ...opts.user, id: this.#b64ToBuffer(opts.user.id) }
    if (opts.excludeCredentials) {
      decoded.excludeCredentials = opts.excludeCredentials.map(c => ({
        ...c,
        id: this.#b64ToBuffer(c.id)
      }))
    }
    return decoded
  }

  #encodeAttestation(credential) {
    return {
      id:    credential.id,
      rawId: this.#bufferToB64(credential.rawId),
      type:  credential.type,
      response: {
        attestationObject: this.#bufferToB64(credential.response.attestationObject),
        clientDataJSON:    this.#bufferToB64(credential.response.clientDataJSON)
      }
    }
  }

  #b64ToBuffer(b64url) {
    const b64 = b64url.replace(/-/g, "+").replace(/_/g, "/")
    const bin = atob(b64)
    const buf = new Uint8Array(bin.length)
    for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i)
    return buf.buffer
  }

  #bufferToB64(buffer) {
    const bytes = new Uint8Array(buffer)
    let bin = ""
    for (const b of bytes) bin += String.fromCharCode(b)
    return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "")
  }

  #handle(error) {
    let key
    if (error?.name === "NotAllowedError")    key = "cancelled"
    else if (error?.name === "NotSupportedError") key = "unsupported"
    else if (!error?.body?.error)             key = "failed"
    // server error string is passed through directly; client keys are announced
    const isError = (key !== "cancelled")
    this.#announce(error?.body?.error || this.#message(key), isError)
    if (this.hasButtonTarget) this.buttonTarget.focus()
  }

  // Announce a message into the status region. Pass isError=true to apply
  // text-danger styling for actual failures; neutral outcomes stay text-text-body.
  #announce(msg, isError = false) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = msg
    this.statusTarget.classList.toggle("text-danger", isError)
    this.statusTarget.classList.toggle("text-text-body", !isError)
  }

  // Read localised error string from a data-webauthn-messages-value JSON blob
  // (falls back to key name so the controller stays functional without wiring)
  #message(key) {
    try {
      const map = JSON.parse(this.element.dataset.webauthnMessagesValue || "{}")
      return map[key] || key
    } catch {
      return key
    }
  }
}

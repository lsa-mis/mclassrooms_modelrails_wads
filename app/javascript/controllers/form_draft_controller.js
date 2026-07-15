import { Controller } from "@hotwired/stimulus"

// ---------- pure helpers (exported for the app's draft_harness page) ----------

const IGNORED_NAMES = new Set(["authenticity_token", "_method"])

export function draftKeyFor(form, keyValue) {
  if (keyValue) return keyValue
  if (form.id) return form.id
  const action = new URL(form.action, window.location.origin)
  return `${action.pathname}:${(form.getAttribute("method") || "get").toLowerCase()}`
}

// Serializes only DESCENDANT controls (spec: form=-attribute outsiders are
// excluded from save AND recover). Hidden values are kept — the Rails
// checkbox hidden-"0" pair is what makes unchecking recoverable — but
// password fields and data-form-draft-ignore fields are skipped entirely.
export function serializeForm(form) {
  const descendantNames = new Set(
    Array.from(form.querySelectorAll("[name]"), (el) => el.name)
  )
  const skipped = new Set(IGNORED_NAMES)
  form
    .querySelectorAll("input[type=password], [data-form-draft-ignore]")
    .forEach((el) => el.name && skipped.add(el.name))

  const formData = new FormData(form)
  const data = {}
  for (const name of descendantNames) {
    if (skipped.has(name)) continue
    const values = formData.getAll(name).filter((v) => typeof v === "string")
    if (values.length === 0) continue
    data[name] = values.length > 1 ? values : values[0]
  }
  return data
}

export function validDraftShape(draft) {
  if (typeof draft !== "object" || draft === null) return false
  if (typeof draft.savedAt !== "number") return false
  if (typeof draft.data !== "object" || draft.data === null) return false
  return Object.values(draft.data).every(
    (v) =>
      typeof v === "string" ||
      (Array.isArray(v) && v.every((x) => typeof x === "string"))
  )
}

export function expired(draft, expiresInHours) {
  return Date.now() - draft.savedAt > expiresInHours * 60 * 60 * 1000
}

// ---------- module-level key cache ----------
// Survives Turbo visits (same JS context); a full reload re-reads the meta.
// The key meta is scrubbed from the DOM on EVERY connect — Turbo head merges
// re-deliver it, and it must never linger (view-source / Save-Page-As /
// snapshot / session-replay leak surface).

let keyPromise = null

function resolveKey() {
  const meta = document.querySelector('meta[name="form-draft-key"]')
  if (meta) {
    const b64 = meta.content
    meta.remove()
    if (!keyPromise) keyPromise = importKey(b64)
  }
  return keyPromise
}

async function importKey(b64) {
  try {
    if (!crypto?.subtle) return null
    return await crypto.subtle.importKey(
      "raw", fromBase64(b64), "AES-GCM", false, ["encrypt", "decrypt"]
    )
  } catch {
    return null
  }
}

const encoder = new TextEncoder()
const decoder = new TextDecoder()

function toBase64(bytes) {
  let binary = ""
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
  }
  return btoa(binary)
}

function fromBase64(b64) {
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))
}

// ---------- controller ----------

export default class extends Controller {
  static targets = ["notice", "status"]
  static values = {
    key: String,
    expiresInHours: { type: Number, default: 48 }
  }

  connect() {
    this.disarmed = false
    this.pendingSave = null
    this.scopeDigest = document.querySelector('meta[name="form-draft-scope"]')?.content
    resolveKey() // scrub + warm the key cache even if this instance no-ops

    this.boundStorage = this.onStorage.bind(this)
    this.boundFlush = this.flush.bind(this)
    this.boundVisibility = this.onVisibilityChange.bind(this)
    this.boundBeforeCache = this.onBeforeCache.bind(this)
    this.boundMorph = this.evaluateReveal.bind(this)
    window.addEventListener("storage", this.boundStorage)
    document.addEventListener("turbo:before-visit", this.boundFlush)
    document.addEventListener("visibilitychange", this.boundVisibility)
    document.addEventListener("turbo:before-cache", this.boundBeforeCache)
    document.addEventListener("turbo:morph", this.boundMorph)

    if (!this.enabled) return
    this.housekeep()
    this.evaluateReveal()
  }

  disconnect() {
    this.cancelPendingSave()
    window.removeEventListener("storage", this.boundStorage)
    document.removeEventListener("turbo:before-visit", this.boundFlush)
    document.removeEventListener("visibilitychange", this.boundVisibility)
    document.removeEventListener("turbo:before-cache", this.boundBeforeCache)
    document.removeEventListener("turbo:morph", this.boundMorph)
  }

  get enabled() {
    return Boolean(this.scopeDigest) && Boolean(window.crypto?.subtle)
  }

  get storageKey() {
    return `draft:v1:${this.scopeDigest}:${draftKeyFor(this.element, this.keyValue)}`
  }

  get suppressKey() {
    return `form-draft-suppress:${this.storageKey}`
  }

  // ---------- actions ----------

  save() {
    if (!this.enabled || this.disarmed) return
    this.cancelPendingSave()
    this.pendingSave = setTimeout(() => this.persist(), 300)
  }

  async recover(event) {
    event.preventDefault()
    const draft = await this.readDraft()
    if (!draft) { this.hideNotice(); return }

    let touched = 0
    for (const [name, value] of Object.entries(draft.data)) {
      const values = Array.isArray(value) ? value : [value]
      this.element
        .querySelectorAll(`[name="${CSS.escape(name)}"]`)
        .forEach((field) => {
          if (field.type === "hidden") return // NEVER write hidden fields back
          if (field.type === "checkbox" || field.type === "radio") {
            field.checked = values.includes(field.value)
          } else if (field instanceof HTMLSelectElement && field.multiple) {
            Array.from(field.options).forEach((opt) => {
              opt.selected = values.includes(opt.value)
            })
          } else {
            field.value = values[0]
          }
          touched += 1
          // Resync sibling controllers (combobox, date picker). This is why
          // auto-submit forms are UNSUPPORTED: dispatching change submits them.
          field.dispatchEvent(new Event("input", { bubbles: true }))
          field.dispatchEvent(new Event("change", { bubbles: true }))
        })
    }

    this.announce(this.statusText("restored").replace("%{count}", String(touched)))
    this.hideNotice()
    this.focusFirstField()
  }

  discard(event) {
    event.preventDefault()
    this.cancelPendingSave()
    this.safely(() => localStorage.removeItem(this.storageKey))
    this.announce(this.statusText("discarded"))
    this.hideNotice()
    this.focusFirstField()
  }

  submitEnd(event) {
    if (event.target !== this.element) return
    if (event.detail.success) {
      // ORDER MATTERS: cancel the trailing debounce BEFORE deleting, and
      // disarm so the redirect's turbo:before-visit flush can't resurrect
      // the draft (zombie-draft panel finding).
      this.cancelPendingSave()
      this.disarmed = true
      this.safely(() => localStorage.removeItem(this.storageKey))
      this.hideNotice()
    } else {
      // 422 re-render already shows the submitted values — suppress the
      // redundant reveal exactly once on the reconnect after the DOM swap.
      this.safely(() => sessionStorage.setItem(this.suppressKey, "1"))
    }
  }

  // ---------- lifecycle handlers ----------

  onStorage(event) {
    if (event.key !== this.storageKey) return
    if (event.newValue === null) {
      // Submitted or discarded in another tab: that tab wins. Stale edits
      // here must not resurrect the cleared draft.
      this.disarmed = true
      this.cancelPendingSave()
      this.hideNotice()
    }
  }

  flush() {
    if (!this.enabled || this.disarmed || !this.pendingSave) return
    this.cancelPendingSave()
    this.persist()
  }

  onVisibilityChange() {
    if (document.visibilityState === "hidden") this.flush()
  }

  onBeforeCache() {
    // Never freeze a revealed notice into the Turbo snapshot cache.
    this.cancelPendingSave()
    this.hideNotice()
  }

  // ---------- persistence ----------

  async persist() {
    this.pendingSave = null
    const key = await resolveKey()
    if (!key || this.disarmed) return
    const payload = JSON.stringify({ savedAt: Date.now(), data: serializeForm(this.element) })
    const blob = await this.encrypt(key, payload)
    if (!blob) return
    this.writeWithQuotaRetry(blob)
  }

  writeWithQuotaRetry(blob) {
    try {
      localStorage.setItem(this.storageKey, blob)
    } catch {
      // One sweep-and-retry; a failed write must never leave a STALE draft
      // standing, so on second failure delete this form's entry.
      this.safely(() => this.housekeep())
      try {
        localStorage.setItem(this.storageKey, blob)
      } catch {
        this.safely(() => localStorage.removeItem(this.storageKey))
      }
    }
  }

  async readDraft() {
    const key = await resolveKey()
    if (!key) return null
    const blob = this.safely(() => localStorage.getItem(this.storageKey))
    if (!blob) return null
    try {
      const draft = JSON.parse(await this.decrypt(key, blob))
      if (!validDraftShape(draft)) throw new Error("shape")
      if (expired(draft, this.expiresInHoursValue)) throw new Error("expired")
      return draft
    } catch {
      this.deleteIfUnchanged(blob)
      return null
    }
  }

  // compare-before-delete: decrypt is async — a fresh valid draft may have
  // landed while a stale blob was being rejected. Only delete what we read.
  deleteIfUnchanged(blob) {
    this.safely(() => {
      if (localStorage.getItem(this.storageKey) === blob) {
        localStorage.removeItem(this.storageKey)
      }
    })
  }

  // AES-256-GCM, 96-bit random IV, 128-bit tag, envelope base64(IV‖ct+tag).
  // The FULL storage key is bound as AAD: a blob relocated to another
  // form/scope/version slot fails the tag (panel finding).
  async encrypt(key, plaintext) {
    try {
      const iv = crypto.getRandomValues(new Uint8Array(12))
      const ct = await crypto.subtle.encrypt(
        { name: "AES-GCM", iv, additionalData: encoder.encode(this.storageKey), tagLength: 128 },
        key, encoder.encode(plaintext)
      )
      const out = new Uint8Array(12 + ct.byteLength)
      out.set(iv)
      out.set(new Uint8Array(ct), 12)
      return toBase64(out)
    } catch {
      return null
    }
  }

  async decrypt(key, blob) {
    const bytes = fromBase64(blob)
    const plaintext = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: bytes.subarray(0, 12), additionalData: encoder.encode(this.storageKey), tagLength: 128 },
      key, bytes.subarray(12)
    )
    return decoder.decode(plaintext)
  }

  // ---------- reveal / housekeeping ----------

  async evaluateReveal() {
    if (!this.enabled) return
    if (this.consumeSuppressMarker()) return
    const draft = await this.readDraft()
    if (!draft || this.disarmed) {
      this.hideNotice()
      return
    }
    if (this.hasNoticeTarget) this.noticeTarget.hidden = false
    this.announce(this.statusText("found"))
  }

  consumeSuppressMarker() {
    return this.safely(() => {
      if (sessionStorage.getItem(this.suppressKey)) {
        sessionStorage.removeItem(this.suppressKey)
        return true
      }
      return false
    })
  }

  // Foreign-scope sweep ONLY (synchronous name comparison, no decryption).
  // Own-scope expiry is handled lazily by readDraft.
  housekeep() {
    this.safely(() => {
      const foreign = []
      for (let i = 0; i < localStorage.length; i += 1) {
        const key = localStorage.key(i)
        if (key?.startsWith("draft:v1:") && !key.startsWith(`draft:v1:${this.scopeDigest}:`)) {
          foreign.push(key)
        }
      }
      foreign.forEach((key) => localStorage.removeItem(key))
    })
  }

  // ---------- notice / announcements / focus ----------

  hideNotice() {
    if (this.hasNoticeTarget) this.noticeTarget.hidden = true
  }

  statusText(kind) {
    return this.hasStatusTarget ? (this.statusTarget.dataset[`${kind}Text`] || "") : ""
  }

  // Small delay so the polite message isn't swallowed by page-load speech.
  announce(message) {
    if (!this.hasStatusTarget || !message) return
    requestAnimationFrame(() => {
      setTimeout(() => { this.statusTarget.textContent = message }, 100)
    })
  }

  focusFirstField() {
    this.element
      .querySelector("input:not([type=hidden]):not([disabled]), select:not([disabled]), textarea:not([disabled])")
      ?.focus()
  }

  // ---------- error posture: any storage failure degrades to feature-off ----------

  cancelPendingSave() {
    if (this.pendingSave) {
      clearTimeout(this.pendingSave)
      this.pendingSave = null
    }
  }

  safely(fn) {
    try {
      return fn()
    } catch {
      return null
    }
  }
}

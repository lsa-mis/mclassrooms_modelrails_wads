---
title: Form drafts
description: Opt-in, client-side recovery for long forms — encrypted snapshots saved to localStorage, expired after 48 hours
keywords: form drafts client-side recovery localStorage encryption draft recovery
---

# Form drafts

Opt-in, client-side draft recovery for long forms. As the user types, an encrypted snapshot of the form is saved to the browser's localStorage; on return, a notice offers **Recover** / **Discard**. Drafts expire after 48 hours and never leave the browser.

## Opting a form in

```erb
<%= form_with model: @thing, id: "thing_form", data: {
      controller: "form-draft",
      action: "input->form-draft#save change->form-draft#save turbo:submit-end->form-draft#submitEnd"
    } do |form| %>
  <%= render "shared/form_draft_notice" %>
  ...fields...
<% end %>
```

**Key requirements:**

- **Form must have an `id`** — `form_with` does not auto-id the form element; the default draft key falls back to `action:method`. Assign an explicit `id:` so drafts are keyed consistently.
- Repeated identical forms on one page must set `data-form-draft-key-value` (e.g., `dom_id(record, :draft)`) to avoid collisions.
- Exclude any field with `data-form-draft-ignore`. Passwords are always excluded, regardless.
- Override expiry per form: `data-form-draft-expires-in-hours-value="24"` (hours, default 48).

## What NOT to attach it to

- **Auth forms** (sign-in, password change, passkeys) — never.
- **Auto-submit forms** — recovery dispatches `change`, which would trigger submission.
- **Hidden-backed widgets** (rich text/Lexxy, custom hidden-input widgets) — only fields whose visible control is authoritative recover correctly. Draftable fields must be DOM descendants of the form (`form=`-attribute outsiders are excluded).

## Security posture

Encryption protects drafts at rest on the device; it does not protect a live session from XSS — CSP and output escaping do.

Drafts are AES-256-GCM-encrypted per user (key derived server-side, delivered via meta tag, imported once and scrubbed from the DOM). A different user on the same browser cannot read them, and their entries are swept on the next user's first draft-enabled page view. Rotating `secret_key_base` invalidates outstanding drafts. Concurrent tabs are last-write-wins. If you add session-replay or DOM-capturing telemetry, scrub the `form-draft-key` before sending. If a form needs drafts with real retention guarantees, use server-side autosave instead — this feature is deliberately not that.

## Expiry and cleanup

Drafts expire after 48 hours. The stored entry is deleted on **Discard**, on a successful submit, or when a read finds it expired or invalid — **Recover** fills the form but leaves the entry in place until one of those events (or the next autosave overwrites it). Pending edits are flushed to storage on Turbo navigation (`turbo:before-visit`) and when the tab is hidden (`visibilitychange`); recovery itself is offered only on the next page render.

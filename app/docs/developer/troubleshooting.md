---
title: Troubleshooting
description: Recovery procedures for dev-environment issues that aren't caught by tests
keywords: troubleshooting stimulus controller assets clobber precompile importmap propshaft tailwind dark mode markdowndocs invitation not delivered block unblock suppressed operations
---

# Troubleshooting

Recovery procedures for environment-state issues. These are problems where the test suite passes but something is wrong at runtime in the browser or terminal. The [Operations](#operations) section at the end covers production questions that arrive as support tickets rather than as failing tests.

## Stimulus controller silently fails to register

**Symptom**: You add `app/javascript/controllers/<name>_controller.js`, place `data-controller="<name>"` on an element, click it — nothing happens. No errors in the DevTools console. `Stimulus.controllers.map(c => c.identifier)` doesn't include your new controller.

**Root cause**: A stale `public/assets/.manifest.json` from a past `bin/rails assets:precompile` run is making Propshaft prefer the static manifest over dynamic resolution. Files added after that precompile aren't in the manifest, so `helper.path_to_asset(...)` returns `nil` for them. Importmap-rails uses `filter_map` with `next unless resolved_path` when serializing the importmap, so those entries are silently dropped — no warning, no error, just a missing controller.

**Fix**:

```bash
bin/rails assets:clobber   # removes public/assets/ and the static manifest
# Ctrl-C the running bin/dev, then restart it
bin/dev
```

Then hard-reload the browser (Cmd-Shift-R). Verify with `Stimulus.controllers.map(c => c.identifier)` in the DevTools console — your controller should now be listed.

**Prevention**: `bin/setup` runs `assets:clobber` automatically, so a fresh setup invocation cures this. Don't run `bin/rails assets:precompile` locally except when deliberately testing the production-equivalent build (e.g., a Kamal smoke test); always clobber afterward.

## Tailwind classes from a gem template don't appear in compiled CSS

**Symptom**: A gem (e.g., markdowndocs) ships ERB templates with Tailwind classes like `dark:bg-slate-900`, but those utilities aren't generated into `app/assets/builds/tailwind.css` and the styling falls back to defaults.

**Root cause**: Tailwind only compiles utilities for classes it scans in source files referenced by `@source` directives. Gem template files installed under `~/.local/share/mise/installs/.../gems/<gem>-<version>/app/views/` aren't in the default scan path.

**Fix**: A `vendor/markdowndocs_views` symlink to the gem's view directory exists for exactly this reason — it gives Tailwind a stable, repo-relative scan target. The `@source` directive in `app/assets/tailwind/application.css` references it:

```css
@source "../../../vendor/markdowndocs_views/**/*.erb";
```

If a class from a gem template still isn't compiling, verify the symlink target points at the right gem version's view directory and re-run `bin/rails tailwindcss:build`.

## Dark mode applies to gem templates but the surface stays light

**Symptom**: `class="dark"` is on `<html>` and most of the app flips correctly, but a section rendered by an external gem (like markdowndocs `/docs/...`) keeps a light background while the text inside flips to light colors — making text invisible.

**Root cause**: The gem hardcodes Tailwind palette pairs like `bg-white dark:bg-slate-800` instead of going through the host's design tokens. CSS-variable-driven tokens (`--color-text-heading`, etc.) propagate via the cascade and flip wherever `.dark` is in scope, but the gem's literal `bg-white` utility wins specificity contests against `dark:bg-slate-800` in some Tailwind v4 cascade orderings, leaving the surface white while the inherited text color flips to its dark-mode value.

**Fix**: Override the gem's templates at `app/views/<engine_name>/...` using your design tokens (`bg-surface-raised`, `text-text-heading`, etc.). Rails view resolution prefers `app/views/` over engine view paths, so the host's overrides take precedence at render time. See the Markdowndocs Integration section of [architecture.md](/docs/developer/architecture#markdowndocs-gem-integration) for how this is wired in this app.

## Operations

Recipes for running the app, rather than for developing it. These arrive as support tickets.

### Why didn't my invitation arrive?

The question arrives undiagnosed, so work the ladder in order rather than jumping to a lookup — the first four rungs are all "the app decided not to send it", and they look identical from the sender's side. Start from the invitation:

```ruby
invitation = Invitation.where(email: "invitee@example.com").order(created_at: :desc).first
```

1. **Magic-link invitation** — `invitation.magic_link?`. There is no recipient address; no email was ever going to arrive. The admin copies and distributes the link themselves.
2. **Blocked by the invitee** — `invitation.suppressed_at` is set, or `InvitationBlock.exists?(inviter: invitation.invited_by, email: invitation.email)`. See [Invitation blocks](/docs/developer/security#invitation-blocks-decline-and-block); unblocking is below.
3. **Suppressed delivery attempts** — `ActivityLog.where(action: "invitation.delivery_suppressed", trackable: invitation)`. One row per refused mailer send. Only the mailer sites record here: the expiring-reminder sweep and its mail leg skip silently by design, so an empty result does not rule out a block.
4. **Sender can't invite** — `invitation.invited_by.can_invite?`. The send surface refuses a sender with no verified email address.
5. **Rate limit** — a resend can be swallowed by `Workspaces::InvitationsController#resend`'s limit of 10 per 3 minutes. The sender sees an alert, but a ticket rarely quotes it.
6. **Queue or transport** — the `deliver_later` job never ran (check Solid Queue) or the mail bounced at the provider.

**Unblocking is two statements, not one:**

```ruby
InvitationBlock.destroy_by(inviter: inviter, email: email)
Invitation.pending.where(invited_by: inviter, email: email).update_all(suppressed_at: nil)
```

`destroy_by`, not `find_by(...).destroy` — the stamp can outlive its block row (an earlier unblock that cleared only the block), and a `NoMethodError` on `nil` is the wrong thing to hand someone already debugging.

Destroying the block alone leaves the stamped invitation invisible to `bulk_invite!`'s duplicate check — which skips only *unsuppressed* pending rows — so every later invite to that address mints another pending duplicate. `update_all` is right here for the same reason the stamping writes are callback-free: clearing the flag is not a workspace-feed event.

After unblocking, **resend the existing invitation** rather than creating a new one. Once the stamp is cleared the row is an ordinary pending invitation again, so a fresh invite to the same address is skipped as a duplicate and nothing is sent — resend is the path that both refreshes the expiry and actually mails.

### Rolling back the invitation-blocks migration

`CreateInvitationBlocksAndSuppression` inverts correctly as *schema*, but rolling it back on a database where the feature has been used raises `SQLite3::ConstraintException`. The old index it restores — `UNIQUE (email, invitable_type, invitable_id) WHERE status = 'pending'` — forbids a shape the new schema deliberately permits: a suppressed pending row (a ghost) sitting beside a live one for the same address and invitable.

Clear the stamps first, then roll back:

```ruby
Invitation.where.not(suppressed_at: nil).update_all(suppressed_at: nil)
```

```bash
bin/rails db:rollback
```

This discards the record of which invitations were suppressed; the `invitation_blocks` rows go with the table, so nothing is left to re-derive it from. Take a database copy first if that matters.

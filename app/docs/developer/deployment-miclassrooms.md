---
title: MiClassrooms Production Deployment
description: MiClassrooms-specific Kamal config, the environment-variable inventory, and the go-live cutover checklist
keywords: deploy kamal production cutover ghcr okta um-api env inventory checklist miclassrooms ssl
---

# MiClassrooms Production Deployment

The fork-specific companion to [Deployment](/docs/developer/deployment), which
covers the template mechanics — the SQLite single-host constraint, SSL config,
storage volumes, health checks, and the production-safety invariants. Everything
here is what MiClassrooms layers on top.

## What's configured

`config/deploy.yml` is set for MiClassrooms:

- **service** `miclassrooms`, **image** `ghcr.io/lsa-mis/miclassrooms` (GitHub Container Registry).
- **SSL** enabled via kamal-proxy — `production.rb` already carries the paired `assume_ssl`/`force_ssl` and the `/up` redirect exclusion, so no app change is needed.
- **Storage** on the `miclassrooms_storage` volume (SQLite DBs + Active Storage under `/rails/storage` — back this up off-server).
- **Env** for the shared-directory tenancy posture, SSO-only auth, and the U-M Facilities gateway sync (inventory below).

The **production-safety invariants** (`max-replicas: 1`, `stop_wait_time: 45`, `RUBY_VERSION` pinned to `.tool-versions`) are unchanged — leave them alone.

## Values to supply before deploy

`config/deploy.yml` ships with `REPLACE_WITH_*` placeholders for values only the
deploying team has. Fill these in — but never commit real **secrets**; those go
through `.kamal/secrets` and the deployer's shell.

| Placeholder | What | Who |
|---|---|---|
| `REPLACE_WITH_PRODUCTION_SERVER_IP` | the one production host (SQLite = single host) | LSA TS |
| `REPLACE_WITH_PRODUCTION_HOSTNAME` | final hostname — `proxy.host`, `RAILS_HOST`, `APP_HOST`; must match DNS + TLS | LSA TS |
| `REPLACE_WITH_OKTA_ISSUER_URL` / `REPLACE_WITH_OKTA_CLIENT_ID` | U-M Okta org + OIDC app | LSA TS |
| `REPLACE_WITH_OWNER_EMAIL` | initial Owner the seed mails a password-set link to | you |
| `UM_API_BASE_URL` / `UM_API_TOKEN_URL` | confirm the production gateway URLs | U-M gateway team |

## Environment variable inventory

Runtime env is injected by Kamal (`env.secret` / `env.clear` in `config/deploy.yml`);
secrets are sourced in `.kamal/secrets` from the deployer's shell or a password manager.

| Variable | Set where | Purpose |
|---|---|---|
| `RAILS_MASTER_KEY` | secret | Rails credentials key (unlocks Google/GitHub OAuth creds) |
| `KAMAL_REGISTRY_PASSWORD` | deployer shell → secret | GHCR push/pull (GitHub PAT, `write:packages`) |
| `SOLID_QUEUE_IN_PUMA` | clear (`true`) | one-box queue topology (jobs run in Puma) |
| `RAILS_HOST` / `APP_HOST` | clear | mailer/absolute URLs / seed owner-setup link |
| `AUTH_SSO_ONLY` | clear (`true`) | production shows only Google + Okta sign-in |
| `ALLOWED_GOOGLE_DOMAINS` | clear | Google sign-in domain allowlist (`umich.edu,lsa.umich.edu`) |
| `OKTA_ISSUER` / `OKTA_CLIENT_ID` | clear | Okta OIDC config |
| `OKTA_CLIENT_SECRET` | secret | Okta OIDC secret |
| `WORKSPACE_ON_SIGNUP` / `TENANCY_WORKSPACE_CREATION` / `TENANCY_SHARED_WORKSPACE_*` / `TENANCY_SHARED_JOIN_ROLE` | clear | single-shared-directory tenancy posture |
| `TENANCY_OWNER_EMAIL` | clear (seed-time) | initial Owner account (`db:seed`) |
| `UM_API_BASE_URL` / `UM_API_TOKEN_URL` | clear | U-M Facilities gateway endpoints (Phase 2 sync) |
| `UM_API_CLIENT_ID` / `UM_API_CLIENT_SECRET` | secret | gateway client credentials |
| `API_UPDATE_DELETE_DRY_RUN` | clear, optional | sync dry-run posture (unset = live writes) |
| `TEST_LOGIN_TOKEN` | **staging only** | Siteimprove crawler login; route never drawn in production |
| Google / GitHub OAuth | Rails credentials | SSO (via `RAILS_MASTER_KEY`) |

**Not yet configured** — these arrive with later Phase 8 tasks and aren't wired
to anything today: Sentry (`SENTRY_*`), TeamDynamix feedback (`TDX_*`), the jobs
dashboard (`JOBS_DASHBOARD_EMAILS`). Add each alongside its task.

## Cutover checklist

Execute in order on go-live day; each box is a gate. Items marked **(later)**
depend on a Phase 8 task not yet built.

- [ ] **DNS + TLS** — hostname → server IP; `proxy.host` / `RAILS_HOST` / `APP_HOST` all match; Let's Encrypt cert issued via kamal-proxy.
- [ ] **Deploy** — all env vars + secrets set; `bin/kamal deploy` green; `bin/kamal console` opens.
- [ ] **Seeds** — reference data verified against the old app's lists (`db:seed`: `CharacteristicDisplayRule`, `UnitDisplayName`, `SyncScopeRule`); Owner account created + password-set link received.
- [ ] **First sync** — run `SyncNightlyJob` from the console; confirm succeeded, inventory counts sane, `Setting.capacity_filter_max` populated. *(Verify via console/logs until the admin sync-run UI ships — later.)*
- [ ] **Legacy URLs in production** — spot-check a known `/classrooms/<facility_code>`, an unknown code, `/classrooms` (LSA pre-filter — confirm `COLLEGE_OF_LSA` resolved), `/legacy_crdb`, one `/toggle_visibile/<rmrecnbr>`.
- [ ] **SSO** — a real U-M user signs in via **Okta** and via **Google**; confirm the domain allowlist and the Okta org gate.
- [ ] **Siteimprove** — `TEST_LOGIN_TOKEN` set on staging; crawler completes an authenticated pass; confirm production 404s `/test_login`.
- [ ] **Backups** — off-server snapshot of `/rails/storage` (SQLite DBs + Active Storage) scheduled before DNS flips.
- [ ] **Privacy + feedback** — real privacy/contact copy live; a working support path. *(later — separate Phase 8 items.)*
- [ ] **Data migration** — if content parity is required, import legacy notes/photos/announcements. *(later — `import_legacy`, Phase 8 Tasks 7–8.)*
- [ ] **Observability** — Sentry receiving events; feedback→TDX smoke. *(later — Phase 8 Tasks 1, 6.)*
- [ ] **Decommission** — old app set read-only, then retire per its own runbook.

---

**Related:** [Deployment (template mechanics)](/docs/developer/deployment) · [Single-tenant preset](/docs/developer/presets-single-tenant) · [Administrator guide](/docs/admin/overview)

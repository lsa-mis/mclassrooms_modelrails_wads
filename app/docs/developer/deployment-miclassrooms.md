---
title: MClassrooms Production Deployment
description: MClassrooms-specific Kamal config, the environment-variable inventory, and the go-live cutover checklist
keywords: deploy kamal production cutover ghcr okta um-api env inventory checklist mclassrooms_modelrails_wads ssl
---

# MClassrooms Production Deployment

The fork-specific companion to [Deployment](/docs/developer/deployment), which
covers the template mechanics — the SQLite single-host constraint, SSL config,
storage volumes, health checks, and the production-safety invariants. Everything
here is what MClassrooms layers on top.

## What's configured

`config/deploy.yml` is set for MClassrooms:

- **service** `mclassrooms_modelrails_wads`, **image** `ghcr.io/lsa-mis/mclassrooms_modelrails_wads` (GitHub Container Registry).
- **SSL** enabled via kamal-proxy — `production.rb` already carries the paired `assume_ssl`/`force_ssl` and the `/up` redirect exclusion, so no app change is needed.
- **Storage** on the `mclassrooms_modelrails_wads_storage` volume (SQLite DBs + Active Storage under `/rails/storage` — back this up off-server).
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
| `SMTP_ADDRESS` (add it under `env.clear`) | the U-M SMTP relay host; left unset on purpose, so production refuses to boot until it is set | LSA TS |

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
| `SMTP_ADDRESS` / `SMTP_PORT` | clear | outbound mail through the U-M SMTP relay (port `587`); the boot guard refuses an unset address |
| `SMTP_USERNAME` / `SMTP_PASSWORD` | secret | U-M SMTP relay credentials |
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
- [ ] **Mail** — `SMTP_ADDRESS` names the U-M relay and its credentials are in the deployer's environment; a mail sent from `bin/kamal console` (for example `Rails.application.config.action_mailer.smtp_settings` checked, then a real `deliver_now`) arrives.
- [ ] **Seeds** — reference data verified against the old app's lists (`db:seed`: `CharacteristicDisplayRule`, `UnitDisplayName`, `SyncScopeRule`); Owner account created + password-set link received.
- [ ] **First sync** — as an operator, open `/operations/sync_runs` and choose **Run now**; reload until it finishes. Confirm it succeeded, every step's counts look sane, the inventory counts match expectations, and `Setting.capacity_filter_max` is populated. Note how long it took: the one-sync lock (`SyncRunJob::DURATION`, 12 hours) must stay well above it. See [Facilities sync](/docs/developer/sync).
- [ ] **Legacy URLs in production** — spot-check a known `/classrooms/<facility_code>`, an unknown code, `/classrooms` (LSA pre-filter — confirm `COLLEGE_OF_LSA` resolved), `/legacy_crdb`, one `/toggle_visibile/<rmrecnbr>`.
- [ ] **SSO** — a real U-M user signs in via **Okta** and via **Google**; confirm the domain allowlist and the Okta org gate.
- [ ] **Siteimprove** — `TEST_LOGIN_TOKEN` set on staging; crawler completes an authenticated pass; confirm production 404s `/test_login`.
- [ ] **Backups** — off-server snapshot of `/rails/storage` (SQLite DBs + Active Storage) scheduled before DNS flips.
- [ ] **Privacy + feedback** — real privacy/contact copy live; a working support path. *(later — separate Phase 8 items.)*
- [ ] **Data migration** — back up `/rails/storage` off-server, copy the legacy export (`media.zip` + `curated.tgz`, unpacked) onto the storage volume, then `bin/kamal app exec 'bin/rails legacy:import EXPORT=/rails/storage/mclassrooms-export WORKSPACE=mclassrooms DRY_RUN=1 REPORT_DIR=/rails/storage/legacy_import/dry-run'` (the container is fresh each time, so reports go on the volume); read the report, run it without `DRY_RUN` and with `REPORT_DIR=/rails/storage/legacy_import/real-run`, then `bin/rails media:warm_variants WORKSPACE=mclassrooms`; once the import is verified, delete the unpacked export and its zips from the volume so they don't ride along in every later backup (keep the reports). Design and runbook: the legacy import spec (2026-09-30).
- [ ] **Observability** — Sentry receiving events; feedback→TDX smoke. *(later — Phase 8 Tasks 1, 6.)*
- [ ] **Decommission** — old app set read-only, then retire per its own runbook.

---

**Related:** [Deployment (template mechanics)](/docs/developer/deployment) · [Single-tenant preset](/docs/developer/presets-single-tenant) · [Administrator guide](/docs/admin/overview)

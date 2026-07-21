---
title: Deployment
description: Deploy ModelRails to production with Kamal — SQLite topology, Solid Queue graduation path, SSL configuration, and the runtime invariants that keep deploys safe.
keywords: kamal deploy production sqlite solid queue max-replicas stop_wait_time graduation rolling deploy ssl https proxy registry github container
---

# Deployment

This template ships with **Kamal** for zero-downtime container deploys to your own server(s). Most of the configuration follows standard Kamal + Rails 8 conventions; this page covers the non-obvious parts that exist *because* this template defaults to SQLite + Solid Queue in-process.

> **Design rationale:** the topology decisions on this page came out of an Ops panel review (Rosa Gutiérrez, Donal McBreen, Aaron Patterson, Nick Janetakis). Full design record at [docs/superpowers/specs/2026-05-18-devcontainer-dockerfile-cleanup-design.md](https://github.com/dschmura/modelrails_base/blob/main/docs/superpowers/specs/2026-05-18-devcontainer-dockerfile-cleanup-design.md).

## The SQLite-on-Rails constraint

This template defaults to **SQLite** (with Solid Queue, Solid Cache, and Solid Cable in-process). SQLite is single-writer and single-host by design — it cannot be shared across machines.

That shapes everything in `config/deploy.yml`:

- `servers.web` runs on **exactly one host** (`max-replicas: 1` enforces this)
- The commented `servers.job:` block is a **trap** for SQLite users — uncommenting it requires migrating to a network-attached database first
- Rolling deploys must **stop the old container before starting the new one** (Kamal's normal start-then-drain behavior would briefly run two containers against the same SQLite file — corruption territory)

The template ships these defaults safely; you only need to think about them when you outgrow SQLite. See [Graduation checklist](#graduation-checklist) below.

## First deploy

### 1. Configure `config/deploy.yml`

Replace placeholders with your real values:

```yaml
servers:
  web:
    hosts:
      - <YOUR-SERVER-IP>   # was: 192.168.0.1
    options:
      max-replicas: 1      # Required for SQLite; do not change

registry:
  server: ghcr.io          # or your registry
  username: your-github-username
  password:
    - KAMAL_REGISTRY_PASSWORD
```

### 2. Set secrets

Add to `.kamal/secrets`:

```bash
KAMAL_REGISTRY_PASSWORD=<your-github-pat-or-registry-token>
RAILS_MASTER_KEY=<contents of config/master.key>
```

Or copy `.env.example` to `.env` for local Kamal commands.

### 3. Bootstrap and deploy

```bash
bin/kamal setup     # First-time only — installs Docker on the host
bin/kamal deploy    # Subsequent deploys
```

The `docker_build` CI job (see [Getting Started](/docs/developer/getting-started)) verifies your production image builds successfully on every PR, so the first time you run `kamal deploy` you're not also debugging Dockerfile issues.

## Production-safety invariants

The template ships three Kamal settings that aren't obvious from the Rails scaffold:

### `max-replicas: 1` on `servers.web.options`

Forces Kamal to **stop the old container before starting the new one** during deploys. Without this, two containers would briefly hold the SQLite file open — `db:prepare` in `bin/docker-entrypoint` races, and SQLite's WAL mode can't always reconcile concurrent boot-time schema work.

When you migrate to a networked DB (Postgres/MySQL), you can remove this constraint and scale `web` horizontally.

### `stop_wait_time: 45` at top level

Kamal's default container-stop grace is 30 seconds. With `SOLID_QUEUE_IN_PUMA: true` (the template default), Solid Queue's `on_worker_shutdown` hook needs longer to drain in-flight jobs before SIGKILL. **45 seconds** is the recommended floor; raise it if you run long-running jobs in-process.

### Builder args pass Ruby version through to the production image

```yaml
builder:
  args:
    RUBY_VERSION: "4.0.6"   # Keep in sync with .tool-versions
```

This ensures `kamal build` always produces an image matching the Ruby version Bundler enforces in `Gemfile.lock`. If `.tool-versions`, `Dockerfile` `ARG RUBY_VERSION`, and `deploy.yml` `builder.args.RUBY_VERSION` ever drift apart, the integration spec at `spec/code_smells/template_invariants_spec.rb` will fail.

## Solid Queue topology

The template ships `SOLID_QUEUE_IN_PUMA: true` in `deploy.yml` env. This runs the Solid Queue **Supervisor inside the web server's Puma process** — one container handles both HTTP requests *and* background jobs.

**This is the right default for the one-box SQLite deploy.** Two containers, one VPS, one `kamal deploy`. No accessory networking. No job-server-can't-reach-SQLite-file issues.

**It is not the right default forever.** Recurring jobs share Puma's GVL with HTTP requests, and a deploy restart can SIGKILL jobs mid-execution if `stop_wait_time` is too low.

### Graduation checklist

When you outgrow this default — typically when you add a second web server, or when sustained job volume exceeds ~10 jobs/sec — follow these four steps **in order**:

1. **Add a database accessory.** Uncomment the `accessories:` block at the bottom of `config/deploy.yml` (it ships with a MySQL template — adapt to Postgres or your preferred DB). Migrate your SQLite data to the new database.

2. **Set `DB_HOST` in `env.clear`.** Point Active Record at the accessory's internal Kamal network address.

3. **Flip `SOLID_QUEUE_IN_PUMA: false`.** This stops the in-Puma supervisor.

4. **Uncomment the `servers.job:` block** in `config/deploy.yml`. This declares a separate `bin/jobs` supervisor host. The image is the same — only the `cmd` differs.

You can now scale `web` horizontally too. Remove `max-replicas: 1` once `web` is no longer pinned to single-host SQLite semantics.

## SSL configuration: paired changes required

When you enable TLS via the Kamal proxy, you **must also** enable the matching settings in `config/environments/production.rb`. These are a package deal — enabling one without the other silently breaks sessions or causes redirect loops.

### The three Rails settings

Uncomment all three in `config/environments/production.rb`:

```ruby
# Trust the SSL-terminating proxy's X-Forwarded-Proto header.
# Without this, Rails sees only the plain HTTP from kamal-proxy
# inside the container, so cookies won't get the Secure flag.
config.assume_ssl = true

# Redirect HTTP → HTTPS, enable Strict-Transport-Security header,
# mark cookies Secure. Requires assume_ssl so the redirect logic
# can detect requests that are already HTTPS via the proxy.
config.force_ssl = true

# Exclude the Kamal health check endpoint from the HTTPS redirect.
# kamal-proxy hits /up over HTTP inside the container — without
# this, health checks 301-redirect and fail, causing Kamal to
# mark the app unhealthy and refuse to roll forward.
config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }
```

### The Kamal proxy setting

At the same time, uncomment in `config/deploy.yml`:

```yaml
proxy:
  ssl: true
  host: yourdomain.com
```

### Why they can't be enabled independently

Valid combinations:

- ✅ All enabled together (proxy + `assume_ssl` + `force_ssl`) → correct production behavior
- ✅ All disabled together → correct for local dev/test (no SSL)

Broken combinations:

- ❌ `assume_ssl` on, no proxy → sessions break (cookies get `Secure` flag but travel over HTTP)
- ❌ `force_ssl` on, no proxy → redirect loop (app redirects to HTTPS, proxy passes requests back as HTTP)
- ❌ `force_ssl` on, `assume_ssl` off, proxy on → redirect loop (app can't detect proxy's HTTPS signal, redirects every request)

### SSL deployment checklist

When preparing the first SSL-enabled deploy, change all of these in the **same commit**:

- [ ] Uncomment `proxy:` block in `config/deploy.yml` with your real domain
- [ ] Uncomment `config.assume_ssl = true` in `config/environments/production.rb`
- [ ] Uncomment `config.force_ssl = true` in `config/environments/production.rb`
- [ ] Uncomment `config.ssl_options = ...` in `config/environments/production.rb`

## Health check

Kamal hits `/up` on the container to determine if a new version is healthy enough to receive traffic. Rails 8 ships this endpoint by default (`Rails::HealthController#show`). The SSL exclusion above keeps it reachable over plain HTTP inside the container's network namespace.

If you customize the health check path, update both:

- `config/deploy.yml` — Kamal proxy's `healthcheck.path` (default `/up`)
- `config/environments/production.rb` — the `ssl_options` redirect exclusion lambda

## Storage volumes

`config/deploy.yml` declares one persistent volume:

```yaml
volumes:
  - "modelrails_base_storage:/rails/storage"
```

This holds:

- The primary SQLite database (`storage/production.sqlite3`)
- Solid Queue's database (`storage/production_queue.sqlite3`)
- Solid Cache (`storage/production_cache.sqlite3`)
- Solid Cable (`storage/production_cable.sqlite3`)
- Active Storage file uploads (if you use disk storage)

**Back this volume up off-server.** Losing it loses your entire app state. The recommended pattern is a periodic snapshot of `/var/lib/docker/volumes/modelrails_base_storage/_data` to S3-compatible storage. Migrating off SQLite to a networked DB only solves part of this — Active Storage attachments still live here unless you also configure S3 storage.

## File serving is already offloaded — don't configure X-Sendfile

The production image runs Thruster in front of Puma, and large-file offload is
**automatic**: Thruster announces sendfile support on every proxied request
(`X-Sendfile-Type: X-Sendfile`), and `Rack::Sendfile` — present in the default
middleware stack — honors that per-request announcement. `send_file` responses,
including Active Storage disk-service downloads, are served by Thruster's Go
process instead of tying up a Puma thread. There is nothing to enable.

**Never set `config.action_dispatch.x_sendfile_header` explicitly** (blog posts
sometimes suggest it). The explicit form applies *unconditionally*: on any
deploy where Thruster isn't in front — a managed platform's nginx, bare
`rails server` — Rack::Sendfile strips the response body and file downloads
return empty, a production-only failure CI can't catch. The announce-per-request
mechanism is deployment-agnostic; leave it alone.

## Common commands

```bash
bin/kamal deploy            # Standard deploy
bin/kamal app logs -f       # Tail container logs
bin/kamal app exec -i 'bin/rails console'   # Console on prod
bin/kamal app exec 'bin/rails db:migrate'   # Run a one-off task
bin/kamal redeploy          # Re-pull image and restart (no rebuild)
bin/kamal rollback          # Revert to the previous deploy
```

Aliases defined in `config/deploy.yml` (you can shortcut these):

```bash
bin/kamal console           # = app exec --interactive --reuse "bin/rails console"
bin/kamal shell             # = app exec --interactive --reuse "bash"
bin/kamal logs              # = app logs -f
bin/kamal dbc               # = bin/rails dbconsole with credentials
```

## Troubleshooting

| Symptom | Likely cause | Where to look |
|---|---|---|
| `bundle install` fails in Docker build with "Could not find version file .tool-versions" | `.tool-versions` not copied before `bundle install` runs | `Dockerfile` — the `COPY Gemfile Gemfile.lock .tool-versions ./` line; regression test in `spec/code_smells/template_invariants_spec.rb` |
| Deploy succeeds but app returns 502 | Health check failing because of HTTPS redirect | `config.ssl_options` excludes `/up` from `force_ssl` redirect |
| Jobs disappear mid-deploy | `stop_wait_time` too short for Solid Queue drain | `config/deploy.yml` `stop_wait_time: 45` or higher |
| `kamal deploy` from devcontainer fails with "docker: command not found" | `docker-outside-of-docker` feature not active | `.devcontainer/devcontainer.json` features; rebuild container |
| Two containers visible during deploy | `max-replicas: 1` missing on `servers.web.options` | Restore the setting; SQLite cannot tolerate this |
| Deploy fails "container not healthy" on a slow boot | Health-check window too tight for the app's boot time | Raise `proxy.healthcheck.timeout` / boot limit in `config/deploy.yml`; with SQLite's stop-then-start deploys, boot time is also your per-deploy downtime — measure it once with a stopwatch |

## Deploying without Kamal

Kamal is this template's default deployment path, not a requirement. Nothing in
app code reads Kamal-specific configuration, so the app runs anywhere that can
provide the contract below — Hatchbox and similar managed platforms included.
Ignore `config/deploy.yml`, `.kamal/`, and `bin/kamal`; leave them in place so
upstream template merges stay clean (see [Forking](forking)).

Run `bin/deploy-guide` to get pointed at the right guide for your target.

### The portable contract

Required on any platform:

| Requirement | Detail |
|---|---|
| `RAILS_MASTER_KEY` | Contents of `config/credentials/production.key` |
| Persistent `storage/` | Writable, survives deploys — holds the SQLite databases and Active Storage files |
| Health check | Rails' built-in `/up` endpoint |
| `SOLID_QUEUE_IN_PUMA=true` | **Without it no background jobs run** (so no emails). Kamal's deploy.yml sets it; a managed platform won't. Alternative: run `bin/jobs` as a separate worker process |
| `RAILS_HOST` | Your app's hostname — mailer links default to `example.com` otherwise |

Optional tuning, all with working defaults: `WEB_CONCURRENCY` (1),
`RAILS_MAX_THREADS` (3), `JOB_CONCURRENCY` (1), `RAILS_LOG_LEVEL` (info).
Preset and seed variables (`SIGNUP_MODE`, `SIGNUP_PERMITTED_JOIN_STRATEGIES`,
`TENANCY_*`) are documented in [Presets](presets) and `.env.example`.

### The constraint that follows you everywhere

SQLite is single-writer, so run **exactly one web instance**. Scaling to a
second server on a managed platform is the same corruption risk as removing
`max-replicas: 1` under Kamal. Graduate to a networked database first (see the
[Solid Queue topology](#solid-queue-topology) graduation checklist above) —
that constraint belongs to the app, not to the deploy tool.

## See also

- [Getting Started](/docs/developer/getting-started) — Dev environment + CI pipeline overview
- [Background Jobs](/docs/developer/background-jobs) — Solid Queue topology, named queues, recurring jobs
- [Security](/docs/developer/security) — Auth, headers, rate limiting
- [Forking](/docs/developer/forking) — Identity rename, fork-owned files, pulling upstream updates
- `config/deploy.yml` — Inline comments document every option (Donal McBreen's "deploy.yml IS the documentation" principle)

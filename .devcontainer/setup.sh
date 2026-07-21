#!/bin/bash
set -e

echo "=== Installing system packages ==="
# Mirror the apt-get packages from the production Dockerfile's base AND build
# stages so the devcontainer's libvips, sqlite3, jemalloc, libyaml and build
# toolchain match prod. Keep this in sync with the Dockerfile's apt-get install
# lines — incl. libssl-dev from the build stage: the webauthn/passkeys gem chain
# (webauthn -> cose -> openssl-signature_algorithm) compiles the native `openssl`
# gem, which needs the OpenSSL headers; the slim base ships only the libssl3
# runtime, not the headers.
sudo apt-get update -qq
sudo apt-get install --no-install-recommends -y \
  build-essential \
  curl \
  git \
  libjemalloc2 \
  libssl-dev \
  libvips \
  libyaml-dev \
  pkg-config \
  sqlite3
sudo rm -rf /var/lib/apt/lists /var/cache/apt/archives

echo "=== Bootstrapping .env ==="
# Convenience only: every var in .env.example has a working default and dotenv
# loads .env only when present, so this just gives the dev a ready file to edit.
if [ ! -f .env ]; then
  cp .env.example .env
  echo "(copied .env.example -> .env)"
else
  echo "(.env already exists — leaving it)"
fi

echo "=== Running bin/setup ==="
# bin/setup is the canonical Rails entry point. It handles bundle install,
# db:prepare and asset clobber idempotently. --skip-server prevents it from
# exec'ing bin/dev inside postCreate (we want the container to come up
# cleanly; the dev runs the server when ready).
bin/setup --skip-server

# Solid Queue's tables live in a separate `queue` database
# (config.solid_queue.connects_to). bin/setup's db:prepare creates and loads it
# on truly-empty storage, but a *preserved* workspace — a container Rebuild
# (vs. delete-and-recreate), or a prior `bin/dev` whose bin/jobs auto-created an
# empty queue file — leaves db:prepare on its no-op migrate path (db/queue_migrate
# is empty; the queue uses schema-load, not migrations), so the solid_queue_*
# tables never appear and bin/jobs crashes the whole `bin/dev` on boot. Self-heal:
# if the table is missing, reset the queue DB from its schema.
if ! bin/rails runner 'exit(SolidQueue::Process.connection.table_exists?("solid_queue_processes") ? 0 : 1)' >/dev/null 2>&1; then
  echo "=== Solid Queue schema missing — resetting the queue database ==="
  bin/rails db:reset:queue
fi

echo "=== Installing Chromium for Cuprite system specs ==="
# System specs drive real headless Chrome via Cuprite/ferrum (pure-Ruby CDP —
# no Node; see spec/support/capybara.rb). CI's ubuntu-latest runners ship Chrome
# pre-installed, but the ruby:slim base does not, so install Debian's chromium
# here (from trixie-security/main) — it lands at /usr/bin/chromium, the name
# ferrum auto-detects on Linux. --no-install-recommends skips ~340 MB of font/
# codec recommends; fonts-liberation is added back for basic text rendering.
# apt-get install is idempotent (no-op once chromium is present).
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends chromium fonts-liberation
sudo rm -rf /var/lib/apt/lists /var/cache/apt/archives

if [ "${CODESPACES:-}" = "true" ]; then
  cat <<'NEXT_STEPS'

=== Dev environment ready (GitHub Codespaces) ===

Next steps:
  1. Run: bin/dev
  2. Open the app: click the port 3000 entry in the PORTS panel (or the
     auto-forward notification) — not http://localhost:3000.
  3. Sign in (passwordless): request a magic link, then read it in the dev
     mail inbox — append /letter_opener to your forwarded port 3000 URL
     (dev never sends real email).

.env was created from .env.example; edit it if you need to change any defaults.
NEXT_STEPS
else
  cat <<'NEXT_STEPS'

=== Dev environment ready ===

Next steps:
  1. Edit .env (copied from .env.example) if you need to change any defaults
  2. Run: bin/dev
  3. Visit: http://localhost:3000

For deployment with Kamal:
  1. Edit config/deploy.yml (server IP, registry, app name)
  2. Set KAMAL_REGISTRY_PASSWORD in .kamal/secrets
  3. Run: bin/kamal setup
NEXT_STEPS
fi

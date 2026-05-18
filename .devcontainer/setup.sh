#!/bin/bash
set -e

echo "=== Installing system packages ==="
# Mirror the apt-get packages installed by the production Dockerfile so the
# devcontainer's libvips, sqlite3, jemalloc, libyaml and build toolchain
# match prod. Keep this list in sync with Dockerfile's apt-get install lines.
sudo apt-get update -qq
sudo apt-get install --no-install-recommends -y \
  build-essential \
  curl \
  git \
  libjemalloc2 \
  libvips \
  libyaml-dev \
  pkg-config \
  sqlite3
sudo rm -rf /var/lib/apt/lists /var/cache/apt/archives

echo "=== Installing Playwright browsers ==="
# Idempotent: skip the ~300MB download if Playwright is already in place
# from a previous postCreate run on the cached bundle volume.
if ! npx --no-install playwright --version > /dev/null 2>&1; then
  npx playwright install --with-deps chromium
else
  echo "(Playwright already installed — skipping)"
fi

echo "=== Running bin/setup ==="
# bin/setup is the canonical Rails entry point. It handles bundle install,
# db:prepare and asset clobber idempotently. --skip-server prevents it from
# exec'ing bin/dev inside postCreate (we want the container to come up
# cleanly; the dev runs the server when ready).
bin/setup --skip-server

cat <<'NEXT_STEPS'

=== Dev environment ready ===

Next steps:
  1. Copy .env.example to .env and fill in any secrets you need
  2. Run: bin/dev
  3. Visit: http://localhost:3000

For deployment with Kamal:
  1. Edit config/deploy.yml (server IP, registry, app name)
  2. Set KAMAL_REGISTRY_PASSWORD in .kamal/secrets
  3. Run: bin/kamal setup
NEXT_STEPS

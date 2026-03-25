#!/bin/bash
set -e

echo "=== Installing runtime versions from .tool-versions ==="
mise install

echo "=== Installing Ruby dependencies ==="
bundle install

echo "=== Installing Playwright browsers ==="
npx playwright install --with-deps chromium

echo "=== Preparing database ==="
bin/rails db:prepare

echo "=== Dev environment ready ==="

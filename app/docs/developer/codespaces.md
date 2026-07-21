---
title: GitHub Codespaces
description: Run ModelRails in a browser-hosted Codespace — boot, magic-link sign-in, and the test suite
keywords: codespaces devcontainer browser cloud dev container github forwarded port host authorization magic link letter opener cuprite
---

# GitHub Codespaces

ModelRails runs in a browser-hosted [GitHub Codespace](https://docs.github.com/en/codespaces) using the same `.devcontainer/` config as a local Dev Container. A Codespace runs that container on a cloud VM and reaches the app through a forwarded HTTPS proxy at `https://<codespace-name>-<port>.app.github.dev` instead of `localhost`.

## Quickstart

1. On the repo's GitHub page: **Code → Codespaces → Create codespace**. The first build runs `.devcontainer/setup.sh` (system packages, `bin/setup`) — a few minutes.
2. In the Codespace terminal: `bin/dev`.
3. Open the app: the **Ports** panel forwards port **3000** — click its URL (or the auto-forward notification). Do not use `http://localhost:3000`.
4. Sign in: ModelRails is passwordless. Request a magic link, then read it in the dev mail inbox at **`/letter_opener`** on your forwarded port **3000** URL (dev never sends real email — `letter_opener_web` mounts there). The link targets the forwarded domain, so it resolves in the browser.

## Why the Codespaces-specific config exists

Two `localhost`-only assumptions break when the origin becomes `*.app.github.dev`, so `config/environments/development.rb` adapts when `CODESPACES=true` (see `lib/codespaces.rb`):

- **Host authorization.** Rails' DNS-rebinding protection allows only `localhost`/IPs by default and returns `403 Blocked host` for the forwarded domain. The Codespaces block adds `.app.github.dev` to `config.hosts`.
- **Mailer link host.** Magic-link emails are built from `config.action_mailer.default_url_options`. In a Codespace that host is set to the forwarded URL (HTTPS, with the port baked into the subdomain) so sign-in links work from the browser.

The server already binds correctly: `.devcontainer/devcontainer.json` sets `BINDING=0.0.0.0`, which `rails server` needs to be reachable through the forward (its development default is `localhost`).

## Running the test suite

`bin/ci` and the Cuprite/axe system specs run entirely in-container against `127.0.0.1`, so they need no Codespaces-specific configuration. The default 2-core Codespace runs the full suite but slowly — if you run `bin/ci` often, bump the machine type from the Codespaces UI (**Change machine type**).

## Out of scope

Passkeys (WebAuthn) over the Codespaces origin and Kamal/Docker builds from inside a Codespace are not configured here.

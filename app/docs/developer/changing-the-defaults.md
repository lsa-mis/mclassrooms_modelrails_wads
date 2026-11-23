---
title: Changing the Defaults
description: Every default a fork starts with, where it's set, and how to change it
keywords: defaults change switch setting configure preset signup open password mail provider backups bucket registry ghcr host hardware kamal ci deploy staging automatic release branch rules approval
---

# Changing the defaults

A fork starts with defaults chosen to get it live with the fewest decisions:
the [quickstart](quickstart) walks through them in order. This page lists each
one, where it's set, and what to change when you want something else. The
linked section has the details.

## Who signs up, and how they sign in

| Setting | Default | To change it | Details |
| --- | --- | --- | --- |
| Tenancy preset | `personal`: every new user gets their own workspace | `bin/fork --preset shared` or `--preset none`, which records it in `.fork.yml`. Choose before launch: changing it later is a data migration. `WORKSPACE_ON_SIGNUP` overrides the recorded choice. | [Presets](presets) |
| Creating more workspaces | `enabled` | `TENANCY_WORKSPACE_CREATION: disabled` under `env.clear` in `config/deploy.yml`, for an app with one shared workspace | [Single-tenant](presets-single-tenant) |
| Sign-up | `invite_only`: an address with no account gets no email | `SIGNUP_MODE: open` under `env.clear` in `config/deploy.yml` | [Open sign-up](deployment#open-sign-up) |
| Password sign-in | Off: the password routes aren't drawn | `AUTH_PASSWORDS: enabled` | [Password sign-in](security#password-sign-in) |

## Where it runs

| Setting | Default | To change it | Details |
| --- | --- | --- | --- |
| Host | One Linux server you rent, deployed with Kamal | Your own hardware runs the same Kamal setup; another platform follows the portable contract | [Hardware you run yourself](deployment#hardware-you-run-yourself), [Deploying without Kamal](deployment#deploying-without-kamal) |
| Image registry | A local registry: images stay on your machines | `registry:` in `config/deploy.yml`, such as GitHub's `ghcr.io` | [Changing the registry](deployment#changing-the-registry) |
| Mail provider | Postmark | `bin/mail-setup`, which also sets up Amazon SES or any SMTP server | [Configure outbound mail](deployment#4-configure-outbound-mail) |
| Backups | Off until you name a destination; then daily | `BACKUP_PATH` for a folder, or `OBJECT_STORAGE_BUCKET` for a bucket, under `env.clear` in `config/deploy.yml`; `BACKUP_SCHEDULE` for how often | [Back up the database](deployment#back-up-the-database) |

## How changes ship

| Setting | Default | To change it | Details |
| --- | --- | --- | --- |
| Branch rules | Solo: a PR merges once `static` and `test` pass, with no approval | `bin/branch-rules` (without `--solo`) requires one approval per PR | [Protect the branches](forking#protect-the-branches) |
| Deploys | From your machine, with `bin/kamal deploy` | The repository variable `DEPLOY_PRODUCTION: true` deploys `main` from CI | [Deploy from CI](deployment#6-deploy-from-ci) |
| Staging | None | A server in `config/deploy.staging.yml`, staging credentials, then the repository variable `DEPLOY_STAGING: true` | [Credentials per deploy](deployment#credentials-per-deploy), [Review on staging](releasing#review-on-staging) |
| Releases | Started by hand with `bin/release prepare` | The repository variable `AUTO_RELEASE: true`, with a `RELEASE_TOKEN` secret | [When a release starts](releasing#when-a-release-starts) |

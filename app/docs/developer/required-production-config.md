---
title: What production needs
description: Every input production needs, grouped by quickstart step, with where it lives, where to get it and how to set it. Generated from the catalog.
keywords: production config credentials env secrets deploy check kamal catalog required
---

# What production needs

This page is generated from `config/required_production_config.yml`, so it
never drifts from the code. It holds no values, only where each one lives and
where to get it. `bin/rails deploy:check` reads the same catalog and tells
you which of these your deploy is still missing.

## Step 4: Production secrets and mail

| Input | Where it lives | Needed | Where to get it | How to set it | Can it be regenerated? |
| --- | --- | --- | --- | --- | --- |
| `SMTP_ADDRESS`: The mail provider's SMTP server | `env.clear` in config/deploy.yml | Always | Your mail provider's SMTP server; bin/mail-setup writes it for Postmark | config/deploy.yml → env.clear | Yes, any time |
| `SMTP_PORT`: The mail provider's SMTP port | `env.clear` in config/deploy.yml | Optional | Your mail provider's SMTP port, usually 587; bin/mail-setup writes it | config/deploy.yml → env.clear | Yes, any time |
| `MAIL_FROM`: The sender address; overrides mailer.from, and with neither set the sender is noreply@ your RAILS_HOST | `env.clear` in config/deploy.yml | Optional | The sender address, such as hello@app.example.org; default noreply@ your RAILS_HOST | config/deploy.yml → env.clear | Yes, any time |
| `secret_key_base`: Signs the session cookie | Encrypted credentials | Always | Written by credentials:edit when it creates the file | bin/rails credentials:edit --environment production | Yes, but a new value signs everyone out |
| `smtp.user_name`: The mail provider login | Encrypted credentials | Always | Your mail provider; for Postmark, the Server API token under Servers → your server → API Tokens | bin/rails credentials:edit --environment production | Yes: make a new token at the provider, put it in both, and deploy |
| `smtp.password`: The mail provider login | Encrypted credentials | Always | Your mail provider; for Postmark, the Server API token under Servers → your server → API Tokens | bin/rails credentials:edit --environment production | Yes: make a new token at the provider, put it in both, and deploy |
| `active_record_encryption.primary_key`: Encrypts personal data at rest | Encrypted credentials | Always | bin/encryption-setup makes all three and stores them only in the production credentials; by hand, bin/rails db:encryption:init prints them once | bin/encryption-setup, or by hand bin/rails credentials:edit --environment production | No, once production has encrypted data: new keys can't read what the old ones wrote |
| `active_record_encryption.deterministic_key`: Encrypts personal data at rest | Encrypted credentials | Always | bin/encryption-setup makes all three and stores them only in the production credentials; by hand, bin/rails db:encryption:init prints them once | bin/encryption-setup, or by hand bin/rails credentials:edit --environment production | No, once production has encrypted data: new keys can't read what the old ones wrote |
| `active_record_encryption.key_derivation_salt`: Encrypts personal data at rest | Encrypted credentials | Always | bin/encryption-setup makes all three and stores them only in the production credentials; by hand, bin/rails db:encryption:init prints them once | bin/encryption-setup, or by hand bin/rails credentials:edit --environment production | No, once production has encrypted data: new keys can't read what the old ones wrote |
| `mailer.from`: The sender address; MAIL_FROM overrides it | Encrypted credentials | Optional | Your choice of sender address | bin/rails credentials:edit --environment production | Yes, any time |
| `oauth.google.client_id`: Offers Google sign-in once its client_id is present | Encrypted credentials | Optional | A google oauth client (OAuth Setup in getting-started) | bin/rails credentials:edit --environment production | Yes, at Google; replace both |
| `oauth.google.client_secret`: Offers Google sign-in once its client_id is present | Encrypted credentials | When `oauth.google.client_id` is set | A google oauth client (OAuth Setup in getting-started) | bin/rails credentials:edit --environment production | Yes, at Google; replace both |
| `oauth.github.client_id`: Offers GitHub sign-in once its client_id is present | Encrypted credentials | Optional | A github oauth app (OAuth Setup in getting-started) | bin/rails credentials:edit --environment production | Yes, at GitHub; replace both |
| `oauth.github.client_secret`: Offers GitHub sign-in once its client_id is present | Encrypted credentials | When `oauth.github.client_id` is set | A github oauth app (OAuth Setup in getting-started) | bin/rails credentials:edit --environment production | Yes, at GitHub; replace both |
| `object_storage.access_key_id`: Lets backups write to the bucket | Encrypted credentials | When `OBJECT_STORAGE_BUCKET` is set | Your backup bucket's provider | bin/rails credentials:edit --environment production | Yes, at the provider |
| `object_storage.secret_access_key`: Lets backups write to the bucket | Encrypted credentials | When `OBJECT_STORAGE_BUCKET` is set | Your backup bucket's provider | bin/rails credentials:edit --environment production | Yes, at the provider |
| `RAILS_MASTER_KEY`: Opens production.yml.enc, so every credentials value | `.kamal/secrets` | Always | config/credentials/production.key, backed up in your password manager, never in git | Read by .kamal/secrets from the environment, fnox, or production.key | No: a new key can't open the old file, so every credentials value would have to be made again |
| `DKIM record`: Lets mail providers verify your mail is signed by you | Your DNS provider | Optional | Your mail provider shows the record to add | Your DNS provider | Yes, at the provider |
| `Return-Path record`: Routes bounces to your mail provider | Your DNS provider | Optional | Your mail provider shows the record to add | Your DNS provider | Yes, at the provider |

## Step 6: Configure the deploy and go live

| Input | Where it lives | Needed | Where to get it | How to set it | Can it be regenerated? |
| --- | --- | --- | --- | --- | --- |
| `RAILS_HOST`: The public hostname every mailer link and redirect points at | `env.clear` in config/deploy.yml | Always | Your app's public domain, such as app.example.org | config/deploy.yml → env.clear | Yes, any time; redeploy |
| `TENANCY_SHARED_WORKSPACE_NAME`: Overrides the workspace name, which otherwise comes from the product name in brand.en.yml | `env.clear` in config/deploy.yml | Optional | A display name for the one shared workspace; default is the product name in brand.en.yml | config/deploy.yml → env.clear | Yes, any time |
| `TENANCY_OWNER_FIRST_NAME`: First name of the owner the first deploy seeds | `env.clear` in config/deploy.yml | Optional | The first name of the person who owns the shared workspace | config/deploy.yml → env.clear | Yes, any time |
| `TENANCY_OWNER_LAST_NAME`: Last name of the owner the first deploy seeds | `env.clear` in config/deploy.yml | Optional | The last name of the person who owns the shared workspace | config/deploy.yml → env.clear | Yes, any time |
| `TENANCY_WORKSPACE_CREATION`: Whether users can create workspaces beyond the shared one; disabled is usual on shared | `env.clear` in config/deploy.yml | Optional | disabled keeps the one shared workspace; see config/deploy.yml's comment | config/deploy.yml → env.clear | Yes, any time |
| `TENANCY_OWNER_EMAIL`: The email of the owner the first deploy seeds on the shared preset | `env.clear` in config/deploy.yml | On the shared preset | The email of the person who owns the shared workspace: yours | config/deploy.yml → env.clear | Yes, any time |
| `SIGNUP_MODE`: Who can sign up; the default is invite_only, so open is a deliberate choice | `env.clear` in config/deploy.yml | Optional | open or invite_only (default invite_only); see Open sign-up in /docs/developer/deployment | config/deploy.yml → env.clear | Yes, any time |
| `APP_HOST`: The host in links printed by tenancy:owner_setup_link and in the seed log | `env.clear` in config/deploy.yml | Optional | Usually the same value as RAILS_HOST; defaults to localhost, so set it or the printed link points at localhost | config/deploy.yml → env.clear | Yes, any time; redeploy |
| `AUTH_PASSWORDS`: Turns on password sign-in; the default is disabled, so sign-in is by magic link or passkey | `env.clear` in config/deploy.yml | Optional | enabled or disabled (default disabled); see Password sign-in in /docs/developer/security | config/deploy.yml → env.clear | Yes, any time; redeploy |
| `SIGNUP_PERMITTED_JOIN_STRATEGIES`: Which join links a workspace may offer; the default is invite, so open_link is a deliberate choice | `env.clear` in config/deploy.yml | Optional | A comma-separated list such as invite,open_link (default invite); see app/docs/developer/presets.md | config/deploy.yml → env.clear | Yes, any time; redeploy |
| `BACKUP_PATH`: The folder daily backups of the database and uploads go to, mounted under volumes | `env.clear` in config/deploy.yml | Optional | A folder on the server mounted under volumes:, such as /backups; see Back up the database in /docs/developer/deployment | config/deploy.yml → env.clear | Yes, any time |
| `OBJECT_STORAGE_BUCKET`: The bucket daily backups go to instead of a folder | `env.clear` in config/deploy.yml | Optional | The name of your bucket at your storage provider; see Move to a bucket in /docs/developer/deployment | config/deploy.yml → env.clear | Yes, any time |
| `BACKUP_SCHEDULE`: When backups run, as any Solid Queue schedule | `env.clear` in config/deploy.yml | Optional | Any Solid Queue schedule, such as every day at 2am; default daily | config/deploy.yml → env.clear | Yes, any time |
| `OBJECT_STORAGE_ENDPOINT`: The bucket provider's endpoint, for anything but AWS | `env.clear` in config/deploy.yml | Optional | Your bucket provider's S3 endpoint URL; needed for anything but AWS | config/deploy.yml → env.clear | Yes, any time |
| `OBJECT_STORAGE_FORCE_PATH_STYLE`: Addresses the bucket by path rather than subdomain, for providers that need it | `env.clear` in config/deploy.yml | Optional | true if your provider needs path-style bucket URLs; see its S3 docs | config/deploy.yml → env.clear | Yes, any time |
| `OBJECT_STORAGE_REGION`: The bucket's region; required once a bucket is set | `env.clear` in config/deploy.yml | When `OBJECT_STORAGE_BUCKET` is set | Your bucket's region, as your storage provider names it | config/deploy.yml → env.clear | Yes, any time |
| `WEBAUTHN_ORIGIN`: The origin passkeys are bound to, when it differs from `https://RAILS_HOST` | `env.clear` in config/deploy.yml | Optional | The https origin of your app, only when it differs from `https://RAILS_HOST` | config/deploy.yml → env.clear | Yes, any time |
| `WEBAUTHN_RP_ID`: The relying-party id passkeys are bound to, when it differs from RAILS_HOST | `env.clear` in config/deploy.yml | Optional | The domain passkeys are bound to, only when it differs from RAILS_HOST | config/deploy.yml → env.clear | Yes, any time |
| `A record for RAILS_HOST`: Points the hostname at the server | Your DNS provider | Optional | Your DNS provider | Your DNS provider | Yes, any time |

A fork adds its own inputs in `config/required_production_config.local.yml`. Run `bin/rails deploy:check` there to see them alongside the ones above.

---
title: Forking
description: Start a downstream app from this template and keep merging upstream improvements
keywords: fork template upstream downstream merge sync rename clone brand seams update jumpstart
---

# Forking this template

ModelRails is an **upstream template**: you clone it to start a product, build in
fork-owned files, and periodically merge upstream improvements back in — the same
workflow commercial Rails templates like Jumpstart Pro use.

Three things make the merges cheap:

1. **Shared git history** — your app is a true clone, so `git merge upstream/main`
   is an ordinary merge.
2. **Fork-owned files** — everything you are expected to rewrite (marketing pages,
   brand strings, your routes, your docs) lives in files upstream never edits again.
3. **A merge driver** — fork-owned paths are marked `merge=ours` in
   `.gitattributes`, so when both you and upstream changed one, the sync keeps
   your version (details in [Fork-owned files](#fork-owned-files)).

**Is this model right for you?** If you just want a starting point and never
plan to pull template improvements, skip the machinery: clone, delete the
`upstream` remote, and own everything (the thoughtbot Suspenders model). This
guide earns its keep when you want upstream fixes and features flowing into
your app for years.

Two pieces of shared machinery already update the easy way — the design system
(`modelrails_ui`) and the docs engine (`markdowndocs`) are gems, so improvements
to them arrive via `bundle update`, no merge involved. The merge workflow covers
everything else: the application code around the gems.

## Start a new app

Create an **empty** private repository on GitHub first (no README, no license — it
must be truly empty). Then:

```bash
git clone git@github.com:dschmura/modelrails_base.git myapp
cd myapp

# The template becomes a read-only "upstream" remote
git remote rename origin upstream
git remote set-url --push upstream DISABLED   # a stray `git push upstream` now fails loudly

# Your new repository becomes origin
git remote add origin git@github.com:YOU/myapp.git
git push -u origin main

# Activate the fork-owned merge driver (bin/setup also does this for you,
# but doing it now means your very first merge is already covered)
git config merge.ours.driver true
```

Two things you'll notice afterwards, both intentional:

- `git remote -v` shows upstream's push URL as `DISABLED`. That string is not a
  real URL — it makes any accidental `git push upstream` fail loudly instead of
  writing to the template.
- Your `main` tracks `origin/main` (your repo), so plain `git pull` stays inside
  your app. Upstream only enters when you explicitly run `git merge upstream/main`.

Finally, record the cut point in the template repo — it answers "which template
version is myapp based on?" forever:

```bash
# in your modelrails_base checkout
git tag forks/myapp-baseline main && git push origin forks/myapp-baseline
```

> **Why not GitHub's "Use this template" button, or a GitHub fork?** "Use this
> template" squashes the entire history into one unrelated commit — every later
> `git merge upstream/main` would need `--allow-unrelated-histories` and conflict
> on everything both sides touched. And GitHub will not fork a repository into
> the account that already owns it. Clone + re-pointed remotes gives you a
> private repo **and** mergeable history.

**Every teammate** who clones your new repository needs the upstream remote once
(`bin/setup` then activates the merge driver automatically — it detects the
remote):

```bash
git remote add upstream git@github.com:dschmura/modelrails_base.git
bin/setup
```

To verify the driver on any clone: `git config merge.ours.driver` should print
`true`. If it prints nothing, fork-owned files will conflict like ordinary files
on your next sync.

## Rename the identity

Do this before your first commit, so the rename is one clean commit you can always
find again.

| What | Where | Notes |
| ---- | ----- | ----- |
| Ruby module name | `config/application.rb` (`module ModelrailsBase`) | `bin/rails app:update` won't do this for you |
| Kamal service name | `config/deploy.yml` (`service:`) | Tags Docker containers; collides if two apps share a host |
| Docker image name | `config/deploy.yml` (`image:`) | Must match your registry path |
| Storage volume names | `config/deploy.yml` (`volumes:`) | Renaming later orphans the old volume — do it before first deploy |
| Brand strings | `config/locales/en/brand.en.yml` | Product name, description, copyright — fork-owned, one file |
| Brand colors | `config/locales/en/brand.en.yml`'s visual twin: `app/assets/tailwind/tokens/_brand.css` | Optional — swap the primary palette family here; re-prove AAA in CI ([Theming](theming)) |
| Marketing copy | `config/locales/en/pages.en.yml` + `app/views/pages/` | Fork-owned — rewrite wholesale |
| PWA app name | `public/manifest.webmanifest` (`name` / `short_name`) | Shown on the home screen if users install the PWA |
| CI image tags | `.github/workflows/ci.yml` + `image_scan.yml` (`tags:`) | Local-only build tags; cosmetic but confusing if stale |
| Devcontainer bundle-cache volume | `.devcontainer/devcontainer.json` | Optional; the invariant spec only checks the `bundle-cache` suffix |
| Session cookie key | optional `config/initializers/session_store.rb` | Only if multiple forks will share a cookie domain |

Then verify nothing was missed:

```bash
grep -ri modelrails . \
  --exclude-dir={.git,tmp,log,coverage,storage,vendor}
bundle exec rspec
```

Expected leftovers: references to the **modelrails_ui** design-system gem
(`Gemfile`, `.modelrails_ui/`, generated component comments) — that's the
library's name, not your app's. Lookbook preview sample copy under
`spec/components/previews/` also mentions ModelRails; rename it or leave it,
nothing asserts on it. The full test suite and CI's production-image build are
the rename's safety net.

## Bootstrap secrets and configuration

The template ships **zero** encrypted credential blobs — your fork generates its
own on first edit:

```bash
bin/rails credentials:edit --environment development
bin/rails credentials:edit --environment production
```

Add OAuth keys and `mailer.from` (structure in [Getting Started](/docs/developer/getting-started)).
Your fork **may** commit its own `.yml.enc` blobs — normal for a private app; the
`.key` files stay gitignored. `.kamal/secrets` reads
`config/credentials/production.key` at deploy time.

For production you'll also set `RAILS_HOST`, pick a tenancy preset
(`WORKSPACE_ON_SIGNUP`), and choose a signup mode — see `.env.example`,
[Presets](presets), and [Deployment](deployment).

## Fork-owned files

These paths are yours. Upstream froze them the day the seams shipped and will
never meaningfully change them again; the `merge=ours` driver keeps your version
on every sync.

| Path | What goes there |
| ---- | --------------- |
| `config/locales/en/brand.en.yml` | Product name, description, copyright |
| `config/locales/en/pages.en.yml` | Marketing copy for your pages |
| `app/views/pages/**`, `app/controllers/pages_controller.rb` | Your marketing/static pages |
| `config/routes/app.rb` | Your product's routes (loaded by `draw(:app)`) |
| `config/markdowndocs_categories.local.yml` | Registers your own docs pages on this `/docs` index |
| `app/assets/tailwind/tokens/_brand.css` | Brand-color overrides — swap the primary palette family ([Theming](theming)) |
| `README.md` | Your product's README |

### Fork seams — method overrides

Beyond file-level seams, a handful of private methods are designed to be overridden in `ApplicationController` (or a concern it includes). These are stable hooks upstream won't break.

#### `authenticated_home_path`

Every post-auth landing routes through this single private method: `SessionsController`, magic-link verification, OAuth callback, registrations, and `redirect_if_authenticated`. The default is `root_path`.

Override it to send signed-in users somewhere other than root:

```ruby
# app/controllers/application_controller.rb
private

def authenticated_home_path
  dashboard_path   # or workspaces_path, events_path, etc.
end
```

This is the primary seam for [Workspace-optional (`:none`)](/docs/developer/presets-none) apps, where post-sign-in landing should be a workspace-agnostic home (a user profile, an event listing, a personal dashboard) rather than a workspace context. But it's useful for any preset — even Solo-default forks often want to land users on `/dashboard` instead of `/`.

### How the merge driver actually behaves

The `merge=ours` driver is a conflict *resolver*, not a wall. During a sync:

- **You customized the file, upstream changed it too** → the driver keeps
  **your** version, silently — no conflict shown. This is the common case: you
  rewrite all of these paths early, that's why they're on the list.
- **You never touched the file, upstream changed it** → upstream's version
  flows in normally. The driver only runs when *both* sides changed a file.

Two consequences worth understanding:

**You can silently miss upstream fixes.** If upstream patches a bug in a file
you've customized (say `pages_controller.rb`), your next sync keeps your version
and the fix never arrives — with no warning. The update recipe below includes a
one-command check for exactly this.

**The driver must be active.** `bin/setup` activates it on any clone that has an
`upstream` remote. Without it, these paths conflict like ordinary files — verify
with `git config merge.ours.driver` → `true`.

`db/seeds.rb` is shared ground rather than fork-owned: everything above the
"Fork seam" marker at the bottom is template-owned; add your domain seeds below
the marker.

### Adding your own docs page

Drop `app/docs/my-feature.md` (same frontmatter as this file), then create
`config/markdowndocs_categories.local.yml`:

```yaml
My Product:
  - my-feature
```

Categories named like template ones ("Guides", "Features") **append** to them;
new names become new index sections. The docs-coverage spec keeps guarding
orphaned pages across both maps automatically.

## Pull upstream updates

### 1. Look before you merge

```bash
git fetch upstream
git log --oneline main..upstream/main   # what's coming
```

Read `CHANGELOG.md` on `upstream/main` first — breaking changes and migrations
are called out under [Unreleased]. If a change sounds structural (schema,
`deploy.yml`), read its PR before merging, not after.

Then check whether upstream touched files **you own** — those changes will NOT
arrive through the merge (the driver keeps yours):

```bash
git log --oneline main..upstream/main -- \
  app/views/pages app/controllers/pages_controller.rb \
  config/locales/en/pages.en.yml config/locales/en/brand.en.yml \
  config/routes/app.rb config/markdowndocs_categories.local.yml \
  app/assets/tailwind/tokens/_brand.css README.md
```

If a commit there looks like a fix you want, cherry-pick it after the merge:
`git cherry-pick <sha>`, then adapt it to your version of the file.

### 2. Merge on a branch

```bash
git checkout -b chore/upstream-sync-$(date +%F)
git merge upstream/main
```

### 3. If you hit conflicts

| Conflict in | Resolution |
| ----------- | ---------- |
| Fork-owned paths | Shouldn't happen — the driver keeps yours. If it does, the driver isn't active: `git merge --abort`, run `git config merge.ours.driver true`, merge again |
| Identity values (`config/deploy.yml` service/image/volumes, `config/application.rb` module) | Keep your names; take any structural changes around them |
| `Gemfile` | Keep **both** sides' gems, then regenerate the lockfile |
| `Gemfile.lock` | Never hand-merge: `git checkout --theirs Gemfile.lock`, then `bundle install`, commit the regenerated result |
| Behavior (app code, specs, config) | Take theirs — unless you deliberately diverged, in which case consider sending your version upstream instead |
| Two migrations, same timestamp | Keep both; rename yours to a later timestamp with `git mv`, then re-run `bin/rails db:migrate` |
| Upstream renamed/moved a file you'd edited | Re-apply your edit at the new location, delete the old file. If the same resolution recurs every sync, turn on `git config rerere.enabled true` so git replays it for you |

A conflict looks like this — your side on top, upstream's below:

```text
<<<<<<< HEAD
    primary_cta: "Start organizing your photos"
=======
    primary_cta: "Get started free"
>>>>>>> upstream/main
```

Decide which line the file should have (here it's your marketing copy — keep
yours), delete the other line and all three marker lines, then `git add` the
file. That's the whole skill; the doctrine table tells you which side to favor.

### 4. Prove the merge

```bash
bin/rails db:migrate    # upstream may ship migrations
bundle exec rspec       # full suite green before the PR
```

Open a pull request into your app's main branch like any other change.

### If something looks wrong after the merge

- **A fork-owned file changed unexpectedly** — the driver wasn't active during
  the merge. Restore your version from before the sync:
  `git restore --source=main <path>`, commit, then fix the driver config.
- **Bundler errors** — regenerate instead of debugging the lockfile:
  `git checkout --theirs Gemfile.lock && bundle install`.
- **Tests fail** — run the failing spec alone, then
  `git diff upstream/main -- <file>` on the code it covers to see whether your
  divergence or the upstream change broke it.

### Cadence

Merge after each meaningful upstream change — don't bank up months of drift.
Small frequent merges conflict less than one big annual one; if upstream is
busy, a fixed weekly sync keeps every merge boring.

## Contribute a fix back

Make template-worthy fixes in a checkout of `modelrails_base` itself (branch →
PR), not in your app — `upstream` is push-disabled by design. If the fix already
exists as a commit in your app:

```bash
cd ../modelrails_base
git checkout -b fix/thing main
git remote add myapp git@github.com:YOU/myapp.git   # or ../myapp for a local checkout
git fetch myapp
git cherry-pick <sha>
```

Three guardrails before you open the PR:

- **Only template-owned files.** If the commit also touches fork-owned paths
  (your README, pages, brand strings), it would pollute the template — split the
  commit, or port the change by hand instead of cherry-picking.
- **Regular commits only, never merge commits** — cherry-picking a merge commit
  needs `-m` and rarely does what you meant.
- **Strip anything product-specific** (names, copy, config values) so the change
  reads as a template improvement.

## Stay mergeable

- **Prefer new files to edited template files** — new files merge clean by
  definition. New models, controllers, components, initializers, docs pages: all
  conflict-free.
- **Brand strings only in `brand.en.yml`** — if you find one hardcoded anywhere
  else, that's an upstream bug; report or fix it upstream.
- **Product routes only in `config/routes/app.rb`** — leave `config/routes.rb`
  to the template.
- **Gemfile: add, don't pin.** Append your gems with loose constraints
  (`"~> 1.0"`); pinning exact versions or git branches conflicts with upstream's
  dependency bumps every sync.
- **Treat `UI::*` primitives as upstream-owned** — extend by composing new
  components rather than editing the primitives; the planned design-system
  update engine will regenerate them.
- **Layouts and shared partials are template-owned but not frozen.** Adding a
  nav link to the header partial is fine — insert lines, don't restructure, so a
  future conflict has one obvious resolution.
- **When you must edit any template file** (an initializer, `application.rb`),
  make the edit additive — append rather than rewrite.

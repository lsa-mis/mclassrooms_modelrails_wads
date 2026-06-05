source "https://rubygems.org"

ruby file: ".tool-versions"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.2", ">= 8.1.2.1"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Auth: OAuth providers and password breach checking
gem "omniauth"
gem "omniauth-google-oauth2"
gem "omniauth-github"
gem "omniauth-rails_csrf_protection"
gem "pwned"
gem "pundit"
gem "pagy"
gem "markdowndocs", "~> 0.8.0"

# User-facing notifications (in-app, email, digest) — see `app/notifiers/`.
gem "noticed", "~> 3.0"

# IDN punycode conversion for email domain canonicalization (EmailNormalizer).
# Already pulled in transitively by capybara/webmock in test, but those are
# dev/test-only — so we declare it explicitly for production.
gem "addressable", "~> 2.8"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 2.0"
# image_processing 2.0 dropped the transitive backend dep; libvips is installed in CI
# (.github/workflows/ci.yml) and the production Dockerfile, and Rails 8.1 defaults
# active_storage.variant_processor to :vips, so we declare ruby-vips explicitly.
# require: false skips Bundler.require — Active Storage's image_processing
# transformer pulls in `vips` lazily on first variant call. active_storage_validations
# also eager-loads its vips analyzer at Rails boot, so libvips must be installed in
# every job that boots Rails (test, scan_js, lint_docs).
gem "ruby-vips", require: false
gem "active_storage_validations"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # N+1 query detection
  gem "bullet"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
end

group :test do
  gem "capybara"
  gem "playwright-ruby-client"
  gem "capybara-playwright-driver"
  gem "simplecov", require: false
  gem "webmock"
  gem "rails-controller-testing"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
  gem "letter_opener"
  gem "letter_opener_web"
  gem "hotwire-spark"
end

gem "axe-core-rspec", "~> 4.11", group: :test
gem "axe-core-api", "~> 4.11", group: :test

gem "lefthook", "~> 2.1", groups: [ :development, :test ], require: false

gem "biscuit-rails", "~> 0.2.1"

gem "lexxy", "~> 0.9.15.alpha"

# Runtime dependency: the vendored app/components/ui/* are ViewComponents and are
# loaded in production. This MUST stay a top-level gem — modelrails_ui (below) only
# GENERATES the components in development and is excluded from production.
gem "view_component", "~> 4.0"

# Runtime dependency of the vendored ApplicationComponent#cn helper: tailwind_merge
# resolves conflicting Tailwind utilities so a per-instance `class:` passthrough
# overrides a component's base utility (e.g. `class: "rounded-full"` beats base
# `rounded-md`). Loaded in production, so it MUST stay a top-level gem.
gem "tailwind_merge"

# Dev-only scaffolding tool that generates app/components/ui/*. Not shipped to
# production; the host app vendors and owns the generated files.
group :development do
  # Pinned to the modelrails/harden integration branch (not a released tag) to pull the
  # `modelrails_ui:agent_rules` generator (gem PR #17). Re-pin to a stable tag after the
  # next gem release. Dev-only, so no production/runtime impact.
  # Setup: run `rails g modelrails_ui:agent_rules` to scaffold your local agent rules
  # (.modelrails_ui/ + a CLAUDE.md import — kept local, like CLAUDE.md itself).
  gem "modelrails_ui", git: "https://github.com/dschmura/modelrails_ui.git", branch: "modelrails/harden"

  # Living documentation / component explorer for the vendored UI::* components
  # (scaffolded by `rails g modelrails_ui:lookbook`). Mounted at /lookbook in
  # development only; previews live in spec/components/previews.
  gem "lookbook"
end

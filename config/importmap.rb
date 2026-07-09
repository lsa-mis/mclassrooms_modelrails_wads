# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "lexxy", to: "lexxy.js"

# ActiveStorage direct upload (MiClassrooms Phase 4 Task 11, Brief §5.3):
# `activestorage.esm.js` ships INSIDE the `activestorage` gem itself
# (app/assets/javascripts/activestorage.esm.js), not as a separately
# fetched npm package — same story as the `@hotwired/*` pins above, whose JS
# ships inside turbo-rails/stimulus-rails. Propshaft's default asset load
# path includes every Railtie's `app/assets/*` (ActiveStorage::Engine is
# `require`d in config/application.rb), so this pin resolves without a CDN
# or a vendored copy. Started in app/javascript/application.js — required
# by the admin bulk-upload flow (app/controllers/admin/bulk_uploads_controller.rb),
# which re-POSTs signed blob ids across two requests and therefore needs the
# blob uploaded to storage BEFORE the first request, not carried as multipart
# form data.
pin "@rails/activestorage", to: "activestorage.esm.js"
pin "cropperjs", to: "https://cdn.jsdelivr.net/npm/cropperjs@2/dist/cropper.esm.js"

# Pannellum (2.5.6 standalone build, bundles libpannellum) is vendored at
# vendor/javascript/pannellum.js rather than fetched from a CDN — it has no
# npm-published ESM build, so `pin "pannellum"` resolves through
# importmap-rails' default vendor/javascript lookup. It sets `window.pannellum`
# as a side effect (no `export`s) — panorama_controller.js lazy-imports it for
# that side effect only, on the visitor's "Load 360°" click.
pin "pannellum"

# Chart.js is opt-in (the gem doesn't bundle it; chart_controller.js lazy-imports it).
# Pinned in development only so the Lookbook catalog can render the chart component —
# this app uses chart solely in the dev-only catalog, so production stays lean and
# downstream apps still opt in themselves.
pin "chart.js", to: "https://cdn.jsdelivr.net/npm/chart.js@4/+esm" if Rails.env.development?

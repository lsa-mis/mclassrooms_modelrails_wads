# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "lexxy", to: "lexxy.js"
pin "cropperjs", to: "https://cdn.jsdelivr.net/npm/cropperjs@2/dist/cropper.esm.js"

# Chart.js is opt-in (the gem doesn't bundle it; chart_controller.js lazy-imports it).
# Pinned in development only so the Lookbook catalog can render the chart component —
# this app uses chart solely in the dev-only catalog, so production stays lean and
# downstream apps still opt in themselves.
pin "chart.js", to: "https://cdn.jsdelivr.net/npm/chart.js@4/+esm" if Rails.env.development?

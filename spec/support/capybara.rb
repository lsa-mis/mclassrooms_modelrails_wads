require "capybara/cuprite"

# System specs drive a real headless Chrome via Cuprite (ferrum — pure-Ruby
# Chrome DevTools Protocol client, no Node). Ferrum auto-detects the browser:
# "Google Chrome" on macOS, google-chrome/chromium on Linux.
#
# These options are passed BOTH to the standalone registration and to
# `driven_by` below, and that duplication is deliberate: Rails' SystemTesting
# ::Driver lists :cuprite as registerable, so `driven_by :cuprite` re-registers
# the driver and overwrites whatever the standalone block set. Options supplied
# only there are silently discarded — the suite ran on ferrum's defaults from
# #497 until #532, which is why the 30s launch budget below never applied.
CUPRITE_DRIVER_OPTIONS = {
  headless: true,
  # Ferrum defaults to 10s. Under the 18-worker parallel suite, that many
  # Chromes racing to spawn regularly blows it and fails the spec with
  # Ferrum::ProcessTimeoutError rather than anything about the page.
  process_timeout: 30,
  timeout: 15,
  # Match the prior Playwright driver: don't raise on page JS console errors.
  js_errors: false,
  # Don't raise Ferrum::PendingConnectionsError when non-essential connections
  # are still in flight at the goto timeout. The Lookbook preview pages
  # (/rails/view_components/...) boot the full explorer harness (fonts, icons,
  # analytics-style assets); under the 18-worker parallel suite — especially
  # once random ordering (#493) de-staggers when workers hit those previews —
  # several Chromes load a preview at once and a slow harness asset trips the
  # 15s timeout, flaking a component's a11y spec that has nothing to do with
  # the harness. Capybara's own have_css/axe waiting still asserts the real
  # content, so a genuinely broken page still fails (just via a matcher
  # timeout, not this error). Standard Cuprite remedy for asset-heavy pages.
  pending_connection_errors: false,
  # Chromium refuses to start as root without --no-sandbox
  # ("Running as root without --no-sandbox is not supported", crbug.com/638180),
  # and the devcontainer's remoteUser is root — so every system spec there failed
  # with `Ferrum::ProcessTimeoutError: Browser did not produce websocket url`,
  # which names neither root nor the sandbox. Docker's 64MB /dev/shm is the
  # second half: Chromium exhausts it mid-run and the tab crashes.
  #
  # Applied only when actually running as root. --no-sandbox gives up a real
  # security boundary, and on a developer's own machine there is no reason to.
  **(Process.uid.zero? ? { browser_options: { "no-sandbox" => nil, "disable-dev-shm-usage" => nil } } : {})
}.freeze

CUPRITE_SCREEN_SIZE = [ 1400, 1400 ].freeze

# Kept so :cuprite resolves for any caller that does not go through
# `driven_by` (e.g. Capybara.javascript_driver below).
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, **CUPRITE_DRIVER_OPTIONS, window_size: CUPRITE_SCREEN_SIZE)
end

Capybara.default_driver = :rack_test
Capybara.javascript_driver = :cuprite

RSpec.configure do |config|
  config.before(:each, type: :system) do
    # Cheap stat, and it turns "132 unexplained contrast failures" into one
    # actionable message. Scoped to :system because nothing else renders CSS.
    CompiledAssetsGuard.verify!

    # .dup because Rails' SystemTesting::Driver mutates the hash it is handed
    # (it deletes :name), which raises on a frozen constant.
    driven_by :cuprite, screen_size: CUPRITE_SCREEN_SIZE, options: CUPRITE_DRIVER_OPTIONS.dup
  end

  config.after(:each, type: :system) do
    Capybara.reset_sessions!
  end
end

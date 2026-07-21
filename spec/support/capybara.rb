require "capybara/cuprite"

# System specs drive a real headless Chrome via Cuprite (ferrum — pure-Ruby
# Chrome DevTools Protocol client, no Node). Ferrum auto-detects the browser:
# "Google Chrome" on macOS, google-chrome/chromium on Linux.
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1400, 1400 ],
    headless: true,
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
    pending_connection_errors: false
  )
end

Capybara.default_driver = :rack_test
Capybara.javascript_driver = :cuprite

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :cuprite
  end

  config.after(:each, type: :system) do
    Capybara.reset_sessions!
  end
end

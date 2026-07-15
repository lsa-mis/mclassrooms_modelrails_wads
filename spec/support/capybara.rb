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
    js_errors: false
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

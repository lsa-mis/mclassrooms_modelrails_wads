require "capybara/playwright"

Capybara.register_driver :playwright do |app|
  Capybara::Playwright::Driver.new(app, browser_type: :chromium, headless: true)
end

Capybara.default_driver = :rack_test
Capybara.javascript_driver = :playwright

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :playwright
  end

  config.after(:each, type: :system) do
    Capybara.reset_sessions!
  end
end

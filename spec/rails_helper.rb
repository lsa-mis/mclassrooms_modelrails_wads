require "simplecov"
# SKIP_COVERAGE: bin/parallel-rspec's dry-run enumeration executes nothing, so
# coverage instrumentation would only add boot time and a bogus sub-minimum
# result.
unless ENV["SKIP_COVERAGE"]
  SimpleCov.start "rails" do
    enable_coverage :branch
    if ENV["TEST_ENV_NUMBER"] # set (possibly "") only under parallel_tests
      # Workers each cover ~1/N of the suite; the 40% floor is enforced on the
      # MERGED result by bin/parallel-rspec's collate step. Keep the floor for
      # single-process runs below. SimpleFormatter: workers skip HTML output so
      # concurrent report writes can't race; collate produces the final HTML.
      command_name "rspec#{ENV['TEST_ENV_NUMBER']}"
      merge_timeout 3600
      formatter SimpleCov::Formatter::SimpleFormatter
      minimum_coverage 0
    else
      command_name "rspec"
      minimum_coverage 40 # keep in sync with bin/parallel-rspec MINIMUM_COVERAGE
    end
  end
end

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
require "capybara/rspec"
require "axe/configuration"
require "webmock/rspec"

WebMock.disable_net_connect!(allow_localhost: true)

Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers

  # ActiveSupport::CurrentAttributes is request-scoped in prod (reset by the
  # executor per request) but NEVER reset between examples in the test process.
  # Model/policy specs that assign Current.workspace/user/project in a `before`
  # leak that value into the next example — an order-dependent flake that only
  # bites when spec ordering happens to line a setter up before a reader.
  # Reset after every example so isolation doesn't depend on load order.
  config.after { Current.reset }
end

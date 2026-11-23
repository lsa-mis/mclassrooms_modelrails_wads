# frozen_string_literal: true

# The instance allows only invite joins by default; an open-link workspace won't save until this permits it.
module SignupHelpers
  def permit_open_join_links
    allow(Rails.configuration.x.signup).to receive(:permitted_join_strategies).and_return(%i[invite open_link])
  end
end

RSpec.configure do |config|
  config.include SignupHelpers
end

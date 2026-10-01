# frozen_string_literal: true

require "view_component/test_helpers"

module ComponentHtml
  def parse(html)
    Capybara.string(html.to_s)
  end
end

RSpec.configure do |config|
  config.include ViewComponent::TestHelpers, type: :component
  config.include ComponentHtml, type: :component
end

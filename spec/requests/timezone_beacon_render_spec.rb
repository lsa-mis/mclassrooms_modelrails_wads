# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Timezone beacon on authenticated pages", type: :request do
  let(:user) { create(:user) }
  let(:beacon) { "[data-controller~='timezone-beacon']" }

  before { sign_in(user) }

  it "renders for a user whose timezone is unset, so the browser can fill it in" do
    user.create_preferences!(timezone: nil)

    get workspaces_path

    expect(Capybara.string(response.body)).to have_css(beacon, visible: :all)
  end

  it "stays off the page once a timezone is set, so a visit sends no PATCH" do
    user.create_preferences!(timezone: "Europe/London")

    get workspaces_path

    expect(Capybara.string(response.body)).to have_no_css(beacon, visible: :all)
  end
end

# frozen_string_literal: true

require "rails_helper"

# Titled iframes per provider, AAA in both themes. Their hosts resolve to nothing
# under test (spec/support/capybara.rb, #1233); the previews stay real in Lookbook.
RSpec.describe "Embed component accessibility", type: :system do
  let(:scope) { [ "[data-test='embed']" ] }

  # The derived src is asserted: the transformation the preview exists to show.
  it "youtube: a titled iframe carrying the derived embed URL; AAA in both themes" do
    visit "/rails/view_components/ui/embed_component/youtube"

    frame = page.find("[data-test='embed'] iframe")
    expect(frame[:title]).to be_present
    expect(frame[:src]).to include("youtube.com/embed/dQw4w9WgXcQ")
    expect_aaa_in_both_themes(include: scope)
  end

  it "map: a titled iframe carrying the derived embed URL; AAA in both themes" do
    visit "/rails/view_components/ui/embed_component/map"

    frame = page.find("[data-test='embed'] iframe")
    expect(frame[:title]).to be_present
    expect(frame[:src]).to include("Eiffel")
    expect_aaa_in_both_themes(include: scope)
  end
end

# frozen_string_literal: true

require "rails_helper"

# A query typed before the search index loads is not dropped (markdowndocs#42, #1074).
# The response is held at the browser; every intercept must continue (cdp_intercept).
RSpec.describe "Docs search — a query typed before the index arrives", type: :system do
  it "runs the query once the index finishes loading" do
    held = nil

    cdp_intercept("search_index") { |request| held = request }

    visit "/docs"

    # Page up, index still in flight: both asserted before typing.
    expect(page).to have_link("Notifications")
    expect(page).to have_link("Welcome")
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until held }

    # "timezone" narrows to one card; found by placeholder (no enable_aria_label).
    fill_in I18n.t("markdowndocs.search_placeholder"), with: "timezone"

    # Held past the 50ms debounce, or the fixed index is already in place and this
    # goes GREEN on the unfixed gem; the version check below guards that.
    sleep 0.3 # waits OUT the 50ms debounce firing against a null index

    # The defect, observed: the query was dropped through showAll().
    expect(page).to have_link("Welcome")
    expect(page).to have_link("Notifications")

    held.continue

    # The disappearance synchronizes on the search having run, so it goes first (#855).
    expect(page).to have_no_link("Welcome")
    expect(page).to have_link("Notifications")
  end
end

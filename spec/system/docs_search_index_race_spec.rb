# frozen_string_literal: true

require "rails_helper"

# markdowndocs#42, filed here as #1074. A query typed before the search index
# finished loading was dropped: `performSearch` returns through `showAll()`
# while `miniSearch` is still null, and nothing re-read the input once the
# fetch resolved. On a slow connection the filter looked dead to anyone who
# started typing straight away.
#
# The fix shipped in the gem WITHOUT a test, deliberately — that repo has no
# JavaScript harness and standing one up means an asset pipeline, an importmap,
# Capybara, Cuprite and a browser in its CI. This app already drives the gem's
# own controller end to end, so the proving spec belongs here.
#
# The race is made deterministic rather than waited on: the index response is
# held at the browser, the query is typed while it is in flight, and only then
# is the response released. `cdp_intercept`'s standing rule applies — every
# intercepted request must get `continue`, `abort` or `respond`, or ferrum
# leaves it hanging.
RSpec.describe "Docs search — a query typed before the index arrives", type: :system do
  it "runs the query once the index finishes loading" do
    held = nil

    # Hold the index request. Non-matching requests are auto-continued by the
    # helper; this one is parked until the query has been typed.
    cdp_intercept("search_index") { |request| held = request }

    visit "/docs"

    # The page itself is up — the cards render server-side — while the index
    # fetch is still outstanding. Assert both, or the typing below could happen
    # before the input exists and prove nothing.
    expect(page).to have_link("Notifications")
    expect(page).to have_link("Welcome")
    Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until held }

    # Typed while the index is demonstrably in flight. "timezone" is the query
    # the sibling filter spec measured: the only term tried whose fuzzy
    # neighbourhood is empty, so it narrows the user-mode index to exactly one
    # card. Located by placeholder because the control's accessible name is an
    # aria-label and `enable_aria_label` is not set for this suite.
    fill_in I18n.t("markdowndocs.search_placeholder"), with: "timezone"

    # The drop has to actually happen, or this proves nothing. `search()`
    # debounces 50ms before calling `performSearch`, so the response must stay
    # held until that timer has fired against a null index — release it sooner
    # and `performSearch` simply runs with the index already in place, which is
    # not this bug. A fixed wait is right here because the thing being waited
    # for is a timer with no observable completion; 6x the debounce is the
    # margin. If it were ever too short the spec would go GREEN on the unfixed
    # gem rather than flake, which is precisely what the version check below
    # guards, and how the first draft of this spec was caught.
    sleep 0.3 # waits OUT the 50ms debounce firing against a null index

    # Nothing filtered: the query was read while `miniSearch` was still null
    # and dropped through `showAll()`. This is the defect, observed.
    expect(page).to have_link("Welcome")
    expect(page).to have_link("Notifications")

    held.continue

    # Order is load-bearing, as in the sibling spec: the non-matching card's
    # DISAPPEARANCE is what synchronizes on the search having run. Asserting the
    # surviving card first would pass against the pre-search state and sample a
    # different moment (#855's end-state trap).
    expect(page).to have_no_link("Welcome")
    expect(page).to have_link("Notifications")
  end
end

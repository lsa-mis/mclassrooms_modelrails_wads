require "rails_helper"

RSpec.describe "Form draft submit lifecycle", type: :system do
  let(:user) { create(:user) }
  before { sign_in_via_form(user) }

  it "clears the draft on successful submit — including the trailing debounce (zombie regression)" do
    visit "/draft_harness"
    fill_in "Title", with: "Ship it"
    wait_for_draft("harness-main")
    # This example assumes the 300ms autosave debounce is still pending at submit-time (on very slow runners it may fire early, narrowing what this example proves).
    fill_in "Notes", with: "typed right before submitting" # schedules a debounce
    within("#harness-main") do
      # pass=1 is the harness's success switch (Task 7); inject it so this
      # POST redirects instead of 422ing (proven pattern: harness_smoke_spec).
      page.execute_script("document.querySelector('#harness-main').insertAdjacentHTML('beforeend', '<input type=hidden name=pass value=1>')")
      click_button "Save"
    end
    expect(page).to have_text("Saved")
    sleep 0.5 # margin for any wrongful resurrection's async encrypt+write to land (via the flush path)
    expect(page.evaluate_script("localStorage.getItem(#{draft_storage_key(user, 'harness-main').to_json}) === null")).to be(true)
  end

  it "keeps the draft on 422 but suppresses the redundant notice on the re-render" do
    visit "/draft_harness"
    fill_in "Title", with: "Invalid attempt"
    wait_for_draft("harness-main")
    within("#harness-main") { click_button "Save" } # no pass=1 injected -> 422
    expect(page).to have_selector("[role=alert]") # 422 re-render
    # draft kept:
    expect(page.evaluate_script("localStorage.getItem(#{draft_storage_key(user, 'harness-main').to_json})")).to be_present
    # notice suppressed on THIS render (the form already shows the values):
    expect(page).to have_selector("#harness-main [data-form-draft-target='notice']", visible: :hidden)
    # and autosave still works on the re-rendered form (blob inequality proves a new save):
    before_blob = page.evaluate_script("localStorage.getItem(#{draft_storage_key(user, 'harness-main').to_json})")
    fill_in "Title", with: "Second try"
    # Poll for blob to change — wait_for_draft alone would return with the old blob still present
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop do
        new_blob = page.evaluate_script("localStorage.getItem(#{draft_storage_key(user, 'harness-main').to_json})")
        break if new_blob != before_blob
        sleep 0.05
      end
    end
    expect(
      page.evaluate_script("localStorage.getItem(#{draft_storage_key(user, 'harness-main').to_json})")
    ).not_to eq(before_blob)
  end

  it "re-offers the draft on a LATER visit after a 422 (suppression is one-shot)" do
    visit "/draft_harness"
    fill_in "Title", with: "Keep me"
    wait_for_draft("harness-main")
    within("#harness-main") { click_button "Save" } # 422
    visit "/draft_harness"
    within("#harness-main") { expect(page).to have_text(I18n.t("form_draft.notice")) }
  end
end

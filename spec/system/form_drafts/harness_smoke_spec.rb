require "rails_helper"

RSpec.describe "Draft harness", type: :system do
  let(:user) { create(:user) }

  it "renders both draft-enabled forms and exposes the pure helpers" do
    sign_in_via_form(user)
    visit "/draft_harness"

    # The harness must render inside the authenticated layout so the
    # form-draft key/scope meta tags are present (spec: key-surface hardening).
    expect(page).to have_selector('meta[name="form-draft-scope"]', visible: false)

    # The main form also mounts the harness bridge controller (space-separated
    # token list), so match on the form-draft token rather than exact string.
    expect(page).to have_selector('form#harness-main[data-controller~="form-draft"]')
    expect(page).to have_selector('form#harness-mini[data-controller="form-draft"]')
    expect(page).to have_field("Title") # archetypes present
    expect(page).to have_field("Published")
    expect(page.evaluate_script("typeof window.formDraftHarness.serializeForm")).to eq("function")
  end

  it "re-renders the form with [role=alert] on POST without pass param" do
    sign_in_via_form(user)
    visit "/draft_harness"

    click_button "Save"

    # POST without pass=1 triggers a 422 re-render with error alert
    expect(page).to have_selector("[role=alert]")
    expect(page).to have_text("Title is invalid")
  end

  it "redirects with success notice on POST with pass param" do
    sign_in_via_form(user)
    visit "/draft_harness"

    # Inject pass=1 hidden field into the form
    page.execute_script("document.querySelector('#harness-main').insertAdjacentHTML('beforeend', '<input type=hidden name=pass value=1>')")

    click_button "Save"

    # POST with pass=1 redirects back to the page with success notice
    expect(page).to have_text("Saved")
  end
end

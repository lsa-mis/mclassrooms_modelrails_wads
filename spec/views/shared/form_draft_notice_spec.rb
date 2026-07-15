require "rails_helper"

RSpec.describe "shared/_form_draft_notice" do
  it "renders the hidden chip, real buttons, and the stable status region" do
    render partial: "shared/form_draft_notice"
    doc = Capybara.string(rendered)

    chip = doc.find('[data-form-draft-target="notice"]', visible: :all)
    # Capybara/Nokogiri reads a valueless boolean attribute (`<div hidden>`) as
    # "" rather than a truthy string, so `be_present` (which is false for "")
    # would wrongly fail here. Assert presence via non-nil instead.
    expect(chip[:hidden]).not_to be_nil
    expect(chip).to have_selector('button[type="button"][data-action="form-draft#recover"]', visible: :all)
    expect(chip).to have_selector('button[type="button"][data-action="form-draft#discard"]', visible: :all)

    status = doc.find('[data-form-draft-target="status"]', visible: :all)
    expect(status[:role]).to eq("status")
    expect(status["aria-live"]).to eq("polite")
    expect(status["data-restored-text"]).to include("%{count}")
    expect(status.text).to eq("") # empty at render; controller writes into it
  end

  it "renders revealed for previews" do
    render partial: "shared/form_draft_notice", locals: { revealed: true }
    expect(Capybara.string(rendered).find('[data-form-draft-target="notice"]', visible: :all)[:hidden]).to be_nil
  end
end

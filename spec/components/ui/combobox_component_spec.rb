# frozen_string_literal: true

require "rails_helper"

# STRUCTURE-only. The combobox's behaviour — filtering, activedescendant, commit,
# focus-out close — is proven by the browser specs. Here: the text input's own
# identity, which is what a `<label for>` and Capybara's `fill_in` need.
RSpec.describe UI::ComboboxComponent, type: :component do
  options = [
    { value: "us", label: "United States" },
    { value: "ca", label: "Canada" }
  ].freeze

  def render_combobox(**opts)
    render_inline(described_class.new(name: "country", options: [
      { value: "us", label: "United States" },
      { value: "ca", label: "Canada" }
    ], **opts))
  end

  # The caller's `id:` lands on the WRAPPER, so without one of its own the text
  # input has no locator a `<label for>` or `fill_in` can reach — only its
  # aria-label, which Capybara ignores unless the host enables aria-label
  # matching. The ledger's system spec had to work around exactly this.
  it "gives the text input an id derived from the wrapper's" do
    render_combobox(id: "country-cb")

    expect(page).to have_css("input[role=combobox]#country-cb-input", visible: :all)
  end

  it "keeps those ids unique across two instances" do
    render_combobox
    first = page.find("input[role=combobox]", visible: :all)[:id]
    render_combobox
    second = page.find("input[role=combobox]", visible: :all)[:id]

    expect(first).to be_present
    expect(first).not_to eq(second)
  end

  it "lets a caller name the input itself" do
    render_combobox(id: "country-cb", input_id: "chosen-country")

    expect(page).to have_css("input[role=combobox]#chosen-country", visible: :all)
    expect(page).to have_no_css("input[role=combobox]#country-cb-input", visible: :all)
  end

  # The hidden input is what the form submits. The visible input stays nameless
  # on purpose: a `name` here would post the typed LABEL alongside the real value.
  it "leaves the text input nameless" do
    render_combobox(id: "country-cb")

    expect(page).to have_css("input[type=hidden][name=country]", visible: :all)
    expect(page).to have_no_css("input[role=combobox][name]", visible: :all)
  end
end

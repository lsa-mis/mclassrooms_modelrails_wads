# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::FloatingLabelComponent, type: :component do
  it "renders a div wrapping a peer input" do
    render_inline(described_class.new(label: "Email"))

    expect(page).to have_css("div.relative input.peer")
  end

  # AAA semantic tokens (the design-token guarantee), not raw Tailwind:
  it "renders with AAA semantic tokens" do
    render_inline(described_class.new(label: "Email"))

    expect(page).to have_css("input.border-border-strong")
    expect(page).to have_css("input.focus-ring")
  end

  it "renders the label text" do
    render_inline(described_class.new(label: "Email address"))

    expect(page).to have_css("label", text: "Email address")
  end

  # The peer-float mechanism: the label must be a LATER SIBLING of the input
  # so `peer-focus:` / `peer-[:not(:placeholder-shown)]:` selectors match.
  it "renders the label after the input as a sibling" do
    render_inline(described_class.new(label: "Email"))

    expect(page).to have_css("div.relative input.peer + label")
  end

  # Label association: the <label for=...> targets the input's id.
  it "associates the label via for matching the input id" do
    render_inline(described_class.new(label: "Email", name: "user[email]"))

    input_id = page.find("input.peer")[:id]

    expect(input_id).not_to be_nil
    expect(page).to have_css("label[for='#{input_id}']", text: "Email")
  end

  # Fallback id: with NEITHER id nor name, the input STILL has an id and the
  # label's `for` matches it (so the control is always labelled).
  it "associates the label even without an id or name" do
    render_inline(described_class.new(label: "Email"))

    input_id = page.find("input.peer")[:id]

    expect(input_id).not_to be_nil
    expect(input_id.to_s).not_to be_empty
    expect(page).to have_css("label[for='#{input_id}']", text: "Email")
  end

  # invalid: drives the server-validation-driven aria-invalid posture and
  # activates the existing `aria-invalid:` style hooks.
  it "sets aria-invalid when invalid" do
    render_inline(described_class.new(label: "Email", invalid: true))

    expect(page).to have_css("input.peer[aria-invalid='true']")
  end

  it "is not invalid by default" do
    render_inline(described_class.new(label: "Email"))

    expect(page).not_to have_css("input[aria-invalid]")
  end

  it "sets required and aria-required when required" do
    render_inline(described_class.new(label: "Email", required: true))

    expect(page).to have_css("input.peer[required][aria-required='true']")
  end

  it "is not required by default" do
    render_inline(described_class.new(label: "Email"))

    expect(page).not_to have_css("input[required]")
    expect(page).not_to have_css("input[aria-required]")
  end

  it "sets aria-describedby when describedby is given" do
    render_inline(described_class.new(label: "Email", describedby: "email_error"))

    expect(page).to have_css("input.peer[aria-describedby='email_error']")
  end

  it "omits aria-describedby by default" do
    render_inline(described_class.new(label: "Email"))

    expect(page).not_to have_css("input[aria-describedby]")
  end
end

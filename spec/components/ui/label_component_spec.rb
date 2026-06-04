# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::LabelComponent, type: :component do
  it "renders a label with text" do
    render_inline(described_class.new("Email address"))

    expect(page).to have_css("label", text: "Email address")
  end

  # A label is NOT an input: it carries no invalid/aria-invalid/describedby.
  it "is not an input" do
    render_inline(described_class.new("Email address"))

    expect(page).not_to have_css("label[aria-invalid]")
    expect(page).not_to have_css("label[aria-describedby]")
  end

  # AAA semantic token (the design-token guarantee), not a raw Tailwind color:
  # text-text-body meets the 7:1 floor on the surface.
  it "renders with the AAA semantic token" do
    render_inline(described_class.new("Email address"))

    expect(page).to have_css("label.text-text-body")
  end

  # Association: for: targets the input's id so clicking the label focuses it.
  it "associates to an input id via for" do
    render_inline(described_class.new("Email address", for: "user_email"))

    expect(page).to have_css("label[for='user_email']", text: "Email address")
  end

  it "omits the for attribute when unset" do
    render_inline(described_class.new("Email address"))

    expect(page).not_to have_css("label[for]")
  end

  # required: renders a decorative asterisk. The marker is aria-hidden — the
  # actual requirement is conveyed on the input (aria-required), never the label.
  it "renders a decorative aria-hidden asterisk when required" do
    render_inline(described_class.new("Email address", required: true))

    expect(page).to have_css("label span[aria-hidden='true']", text: "*")
  end

  it "is not required by default" do
    render_inline(described_class.new("Email address"))

    expect(page).not_to have_css("label span[aria-hidden='true']")
  end

  # The visible label text is still present alongside the required marker.
  it "keeps the label text when required" do
    render_inline(described_class.new("Email address", required: true))

    expect(page).to have_css("label", text: "Email address")
  end

  # Block content takes precedence over the text arg (the wrapping pattern).
  it "renders block content" do
    render_inline(described_class.new(for: "user_name")) { "Full name" }

    expect(page).to have_css("label[for='user_name']", text: "Full name")
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::CopyComponent, type: :component do
  let(:url) { "https://example.test/invitations/abc123/accept" }

  def render_copy(**opts)
    render_inline(described_class.new(value: url, label: "Invitation link", **opts))
  end

  it "renders the readonly value with a real label and the outline/neutral trigger" do
    render_copy

    expect(page).to have_css("input[readonly][data-copy-target='source'][value='#{url}']")
    expect(page).not_to have_css("input[name]")
    id = page.find("input[data-copy-target='source']")[:id]
    expect(page).to have_css("label[for='#{id}']", text: "Invitation link")
    expect(page).to have_css("button.btn-secondary[aria-label='Copy Invitation link'][data-action='copy#copy']", text: "Copy")
  end

  it "pre-registers both live regions, empty" do
    render_copy

    expect(page).to have_css("p[role='status'][aria-live='polite'][data-copy-target='status']", exact_text: "")
    expect(page).to have_css("p[role='alert'][data-copy-target='error']", exact_text: "")
  end

  it "resolves the host's own locale keys, which name no keystroke and never the value" do
    expect(I18n.t("modelrails_ui.copy.action")).to eq("Copy")
    expect(I18n.t("modelrails_ui.copy.button_label", action: "Copy", label: "x")).to eq("Copy x")
    expect(I18n.t("modelrails_ui.copy.copied", label: "x")).to eq("Copied x to the clipboard")
    expect(I18n.t("modelrails_ui.copy.failed", label: "x")).not_to include("Ctrl")
    expect(I18n.t("workspaces.invitations.index.magic_link_aria")).to eq("Invitation link")
  end
end

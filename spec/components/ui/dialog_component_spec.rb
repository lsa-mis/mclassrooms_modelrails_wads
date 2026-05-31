# frozen_string_literal: true

require "rails_helper"

# Parity gate: UI::DialogComponent must render the app's native-<dialog> modal
# markup (shared/_modal) and drive the proven `modal` Stimulus controller, so it
# is a drop-in replacement. Behavior is covered by system/modal_spec.rb (which
# tests the `modal` controller); this spec locks the markup/ARIA contract.
RSpec.describe UI::DialogComponent, type: :component do
  def render_dialog
    render_inline(described_class.new(title: "Edit profile", description: "Update your details", size: :lg)) do |d|
      d.with_trigger { '<button type="button">Open</button>'.html_safe }
      "Body content".html_safe
    end
  end

  it "renders a native <dialog> with modal ARIA + targets" do
    render_dialog
    dlg = page.find("dialog")
    expect(dlg["role"]).to eq("dialog")
    expect(dlg["aria-modal"]).to eq("true")
    expect(dlg["aria-labelledby"]).to be_present
    expect(dlg["aria-describedby"]).to be_present
    expect(dlg["data-modal-target"]).to eq("dialog")
  end

  it "wraps in the modal controller and wires the trigger to modal#open" do
    render_dialog
    expect(page).to have_css('[data-controller="modal"]')
    expect(page).to have_css('[data-action="click->modal#open"]')
    expect(page).to have_text("Open")
  end

  it "renders the panel (surface-overlay, size), title, and an accessible close button" do
    render_dialog
    expect(page).to have_css('[data-modal-target="panel"].bg-surface-overlay.max-w-2xl')
    expect(page).to have_css("h2", text: "Edit profile")
    expect(page).to have_css('button.btn-touch-target[data-action="click->modal#close"]')
    expect(page).to have_text("Body content")
    expect(page).to have_text("Update your details")
  end

  # Easy-adoption mode: render ONLY the <dialog> for embedding in an app that
  # already owns the data-controller="modal" wrapper + trigger (e.g. shared/_modal),
  # with a fixed body_id to preserve a Turbo Stream contract.
  it "embedded mode (wrapper: false) renders only the dialog with the given body_id" do
    render_inline(described_class.new(title: "T", description: "d", wrapper: false, body_id: "modal-body"))

    expect(page).not_to have_css('[data-controller="modal"]')
    expect(page).to have_css("dialog[data-modal-target='dialog']")
    expect(page).to have_css("#modal-body")
  end
end

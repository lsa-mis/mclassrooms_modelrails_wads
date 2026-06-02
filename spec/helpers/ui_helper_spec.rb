# frozen_string_literal: true

require "rails_helper"

RSpec.describe UIHelper, type: :helper do
  it "renders the named UI:: component, forwarding positional + keyword args" do
    rendered = nil
    allow(helper).to receive(:render) { |component| rendered = component }
    helper.ui(:button, "Save", variant: :primary)
    expect(rendered).to be_a(UI::ButtonComponent)
  end

  it "camelizes multi-word names (file_input -> UI::FileInputComponent)" do
    rendered = nil
    allow(helper).to receive(:render) { |component| rendered = component }
    helper.ui(:file_input, name: "user[avatar]")
    expect(rendered).to be_a(UI::FileInputComponent)
  end

  it "raises NameError on an unknown component name (boundary guard)" do
    expect { helper.ui(:totally_not_a_component) }.to raise_error(NameError)
  end
end

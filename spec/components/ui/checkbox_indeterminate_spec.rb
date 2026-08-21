# frozen_string_literal: true

require "rails_helper"

# `indeterminate` is a DOM property with no HTML attribute, so it cannot be rendered —
# a controller sets it on connect. The markup therefore only DECLARES the intent, and the
# native `:indeterminate` state (and the AT announcement that rides on it) follows.
RSpec.describe "UI::CheckboxComponent indeterminate", type: :component do
  def checkbox(**opts) = render_inline(UI::CheckboxComponent.new(label: "Select all", **opts))

  it "declares nothing extra by default" do
    checkbox

    expect(page).to have_no_css("[data-controller~=indeterminate]")
  end

  it "wires the controller that sets the DOM property" do
    checkbox(indeterminate: true)

    expect(page).to have_css("input[type=checkbox][data-controller~=indeterminate]")
  end

  # A tri-state parent is conceptually "some children checked", never "checked" itself,
  # so the checked attribute must not ride along and win in the form payload.
  it "does not also mark the input checked" do
    checkbox(indeterminate: true)

    expect(page.find("input")[:checked]).to be_falsey
  end

  it "still allows an explicitly checked box to be indeterminate-first" do
    checkbox(indeterminate: true, checked: true)

    expect(page).to have_css("input[data-controller~=indeterminate]")
  end
end

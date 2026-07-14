require "rails_helper"

RSpec.describe "rooms/_characteristic_chip", type: :view do
  def chip(description: nil)
    RoomPresenter::Chip.new(
      short_code: "projdigit", label: "Projector",
      description: description, icon_name: :check_circle, team_learning: false
    )
  end

  it "renders a quiet outline badge by default (room-page / remainder treatment)" do
    render partial: "rooms/characteristic_chip", locals: { chip: chip }
    expect(rendered).to have_css("span.border-border", text: "Projector")
    expect(rendered).to have_no_css("span.bg-interactive-subtle")
  end

  it "renders the emphasized soft/interactive badge when emphasis: true" do
    render partial: "rooms/characteristic_chip", locals: { chip: chip, emphasis: true }
    expect(rendered).to have_css("span.bg-interactive-subtle", text: "Projector")
  end

  it "wraps a described chip in the supplementary tooltip" do
    render partial: "rooms/characteristic_chip",
           locals: { chip: chip(description: "Fixed data projector") }
    expect(rendered).to include("Fixed data projector")
  end
end

require "rails_helper"

RSpec.describe "Describable contract (CI ratchet)" do
  before { Rails.application.eager_load! }

  # A blank interpolation doesn't only strand a trailing preposition
  # ("...rack in "); mid-sentence templates (room.front/back/inner_door)
  # collapse the surrounding space into a double space or a space-then-comma
  # instead ("...front of  from..." / "...door of , photographed..."). This
  # one pattern is shared by both examples below so they cannot drift apart:
  # the first asserts real output never matches it, the second proves a
  # deliberately blanked rendering DOES — so narrowing this back to a
  # trailing-only check turns the second example red.
  blank_interpolation = /\s{2,}|\s,|\s\z/

  it "every registered slot has a non-blank derived backstop and stored-wins" do
    Describable.registry.values.uniq.each do |model|
      model.describable_slots.each_key do |slot|
        rec = build(model.model_name.singular.to_sym, "#{slot}_alt": nil)
        expect(rec.alt_for(slot)).to be_present, "#{model}##{slot} backstop was blank"
        expect(rec.alt_for(slot)).not_to match(blank_interpolation),
          "#{model}##{slot} interpolated an empty value"

        rec.write_attribute("#{slot}_alt", "stored wins")
        expect(rec.alt_for(slot)).to eq("stored wins")
      end
    end
  end

  # Self-test for the assertion above: proves blank_interpolation actually
  # catches what it exists to catch, rather than resting on a manual check
  # that has since left no trace in the suite. Without this, the example
  # above passes for the wrong reason — none of the four factories ever
  # produce a blank name, so the pattern is never actually exercised, and a
  # future edit narrowing it back to trailing-only would not be caught here.
  it "blank_interpolation matches a deliberately blank rendering, for every consumer" do
    # Building, Floor, and Room derive their alt straight from an owned name
    # via I18n.t inside the registered lambda, with no guard in front of it
    # (the latent hole task-9-report.md documents and this plan deliberately
    # does not close). Call each model's OWN registered lambda — the exact
    # code path `alt_for` uses in production — with the name-bearing
    # attribute forced blank via `build` (which skips validations), to prove
    # the pattern would catch the hole if it were ever exercised.
    blank_building = build(:building, name: "")
    expect(Building.describable_slots.fetch(:photo).call(blank_building))
      .to match(blank_interpolation)

    blank_floor = build(:floor, building: blank_building)
    expect(Floor.describable_slots.fetch(:plan).call(blank_floor))
      .to match(blank_interpolation)

    blank_room = build(:room, facility_code: nil, building_name: nil, room_number: nil, nickname: nil)
    expect(Room.describable_slots.fetch(:panorama).call(blank_room))
      .to match(blank_interpolation)
    expect(Room.describable_slots.fetch(:seating_chart).call(blank_room))
      .to match(blank_interpolation)

    # MediaAsset's own derived_alt raises BlankOwnerName before a blank name
    # ever reaches I18n.t (see MediaAsset#base_derived_alt) — that guard IS
    # this task's fix, so a blank rendering can no longer be produced by
    # calling the model at all. Go at the locale templates it reads from
    # directly instead: the six Room::SUBJECTS keys — three of which
    # (front, back, inner_door) interpolate %{owner} mid-sentence, the exact
    # shape a trailing-only pattern used to miss — plus the NULL-subject
    # gallery_image fallback MediaAsset keeps under its own key.
    Room::SUBJECTS.each_value do |entry|
      expect(I18n.t(entry.fetch(:key), owner: "")).to match(blank_interpolation)
    end
    expect(I18n.t("media.derived_alt.gallery_image", room: "")).to match(blank_interpolation)
  end

  it "image-bearing factories default to authored (no new needs_review content)" do
    %i[building floor room media_asset].each do |fac|
      rec = build(fac)
      model = rec.class
      model.describable_slots.each_key do |slot|
        expect(rec.alt_status_for(slot)).to eq(:authored),
          "factory :#{fac} left #{model}##{slot} in #{rec.alt_status_for(slot)}"
      end
    end
  end
end

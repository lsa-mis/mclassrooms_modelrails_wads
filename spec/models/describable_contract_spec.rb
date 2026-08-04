require "rails_helper"

RSpec.describe "Describable contract (CI ratchet)" do
  before { Rails.application.eager_load! }

  it "every registered slot has a non-blank derived backstop and stored-wins" do
    Describable.registry.values.uniq.each do |model|
      model.describable_slots.each_key do |slot|
        rec = build(model.model_name.singular.to_sym, "#{slot}_alt": nil)
        expect(rec.alt_for(slot)).to be_present, "#{model}##{slot} backstop was blank"
        expect(rec.alt_for(slot)).not_to match(/\s\z|\sin \z|\sof \z/),
          "#{model}##{slot} interpolated an empty value"

        rec.write_attribute("#{slot}_alt", "stored wins")
        expect(rec.alt_for(slot)).to eq("stored wins")
      end
    end
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

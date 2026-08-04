FactoryBot.define do
  factory :media_asset do
    owner { association(:room) }
    workspace { owner.workspace }
    position { 1 }
    image_alt { "Gallery photo" }

    after(:build) do |asset|
      asset.image.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "gallery.png",
        content_type: "image/png"
      )
    end

    # The ratchet in describable_contract_spec requires the DEFAULT factory to
    # produce :authored, so image_alt above is not optional.
    trait :needs_alt do
      image_alt { nil }
      image_derived_ok { false }
    end

    trait :derived_ok do
      image_alt { nil }
      image_derived_ok { true }
    end

    trait :unclassified do
      subject { nil }
    end

    # Exactly what a row looks like after media:import, so import, worklist and
    # coverage specs share one definition.
    trait :imported do
      subject { nil }
      image_alt { nil }
      image_derived_ok { false }
    end
  end
end

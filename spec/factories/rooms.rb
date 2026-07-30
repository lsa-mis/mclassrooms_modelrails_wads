FactoryBot.define do
  factory :room do
    building
    # Overriding :workspace does NOT propagate to the auto-built building —
    # pass building: explicitly (in the same workspace) when you override
    # workspace, or the room and its building land in different tenants.
    workspace { building.workspace }
    sequence(:rmrecnbr) { |n| (2_000_000 + n).to_s }
    sequence(:room_number) { |n| format("%04d", n) }
    room_type { "Classroom" }
    sequence(:facility_code) { |n| "MLB#{format('%04d', n)}" }
    instructional_seat_count { 40 }
    building_name { building.name }
    in_feed { true }

    trait :hidden do
      hidden_at { Time.current }
      hidden_by factory: :user
    end

    # Minimal panorama attachment for specs exercising Room#panorama /
    # alt_for(:panorama) rendering — reuses the shared room.jpg fixture
    # (spec/system/rooms/show_spec.rb attaches the same fixture to
    # room.panorama directly; this trait just gives factory-only specs the
    # same attachment without a manual `after(:create)` in every spec).
    trait :with_panorama do
      after(:build) do |room|
        room.panorama.attach(
          io: Rails.root.join("spec/fixtures/files/room.jpg").open,
          filename: "panorama.jpg",
          content_type: "image/jpeg"
        )
      end
    end
  end
end

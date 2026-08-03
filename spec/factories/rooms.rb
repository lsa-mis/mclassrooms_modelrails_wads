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
    photo_alt { "Room photo" }
    panorama_alt { "Room panorama" }
    seating_chart_alt { "Seating chart" }

    trait :hidden do
      hidden_at { Time.current }
      hidden_by factory: :user
    end

    trait :needs_alt do
      photo_alt { nil }
      photo_derived_ok { false }
      panorama_alt { nil }
      panorama_derived_ok { false }
      seating_chart_alt { nil }
      seating_chart_derived_ok { false }
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

    # A GENUINELY 2:1 source. :with_panorama attaches room.jpg (200x200) — fine
    # for alt-text specs, geometrically meaningless for the projection, which
    # rejects anything not equirectangular. Never wrap a :with_panorama room in
    # perform_enqueued_jobs: the render job will raise NotEquirectangular.
    trait :with_equirect_panorama do
      after(:build) do |room|
        room.panorama.attach(io: Rails.root.join("spec/fixtures/files/equirect.png").open,
                             filename: "panorama.png", content_type: "image/png")
      end
    end

    # The DERIVED attachment, without running vips — for view specs that only
    # need `flat_panorama.attached?` to be true.
    trait :with_flat_panorama do
      after(:build) do |room|
        room.flat_panorama.attach(io: Rails.root.join("spec/fixtures/files/equirect.png").open,
                                  filename: "flat.png", content_type: "image/png")
      end
    end
  end
end

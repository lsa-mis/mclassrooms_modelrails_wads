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
  end
end

FactoryBot.define do
  factory :availability_block do
    room
    # Landmine (see spec/factories/rooms.rb): overriding :workspace does NOT
    # propagate to an auto-built room — pass room: explicitly (in the same
    # workspace) when overriding workspace, or they land in different tenants.
    workspace { room.workspace }
    starts_at { 1.hour.from_now }
    ends_at { 2.hours.from_now }
  end
end

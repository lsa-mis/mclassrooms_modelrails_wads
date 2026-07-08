FactoryBot.define do
  factory :room_characteristic do
    room
    workspace { room.workspace }
    sequence(:code, &:to_s)
    short_code { "InstrComp" }
  end
end

FactoryBot.define do
  factory :floor do
    building
    workspace { building.workspace }
    sequence(:label, &:to_s)
  end
end

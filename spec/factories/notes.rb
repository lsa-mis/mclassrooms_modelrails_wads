FactoryBot.define do
  factory :note do
    notable factory: :room
    # Landmine (see spec/factories/rooms.rb): overriding :workspace does NOT
    # propagate to an auto-built notable — pass notable: explicitly (in the
    # same workspace) when overriding workspace, or they land in different
    # tenants.
    workspace { notable.workspace }
    author factory: :user
    body { "A note" }
    alert { false }

    trait :alert do
      alert { true }
    end

    trait :reply do
      parent factory: :note
    end
  end
end

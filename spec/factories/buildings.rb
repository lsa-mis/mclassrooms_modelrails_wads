FactoryBot.define do
  factory :building do
    workspace
    sequence(:bldrecnbr) { |n| (1_000_000 + n).to_s }
    sequence(:name) { |n| "Building #{n}" }
    in_feed { true }

    trait :hidden do
      hidden_at { Time.current }
      hidden_by factory: :user
    end

    trait :not_in_feed do
      in_feed { false }
    end
  end
end

FactoryBot.define do
  factory :building do
    workspace
    sequence(:bldrecnbr) { |n| (1_000_000 + n).to_s }
    sequence(:name) { |n| "Building #{n}" }
    in_feed { true }
    photo_alt { "Building exterior" }

    trait :hidden do
      hidden_at { Time.current }
      hidden_by factory: :user
    end

    trait :not_in_feed do
      in_feed { false }
    end

    trait :needs_alt do
      photo_alt { nil }
      photo_derived_ok { false }
    end
  end
end

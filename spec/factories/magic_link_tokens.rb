FactoryBot.define do
  factory :magic_link_token do
    email { Faker::Internet.email }
    token_digest { MagicLinkToken.digest(SecureRandom.urlsafe_base64(32)) }
    expires_at { 1.hour.from_now }

    trait :consumed do
      consumed_at { Time.current }
    end

    trait :expired do
      expires_at { 1.hour.ago }
    end
  end
end

FactoryBot.define do
  # Sequence prefixes keep the unique (provider, uid) index satisfied by
  # construction, not by the PRNG's luck — #456's collision class, removed at
  # the source (#856). The random tails keep each provider's real uid shape
  # (Google ~21 numeric digits, GitHub a shorter numeric id).
  sequence(:google_uid) { |n| format("%08d%s", n, Faker::Number.number(digits: 13)) }
  sequence(:github_uid) { |n| format("%06d%s", n, Faker::Number.number(digits: 8)) }

  factory :authentication do
    # This factory exists to create the authentication, so its user must not
    # arrive already holding one — the :user default is a verified email row,
    # and provider is unique per user (#850).
    association :user, factory: [ :user, :no_authentications ]
    provider { "email" }
    # No uid: the model assigns the user's id for email rows (#903), which is
    # what production does and is unique by construction. OAuth traits below
    # supply their own, because nothing assigns those.

    trait :google do
      provider { "google" }
      uid { generate(:google_uid) }
      oauth_token { SecureRandom.hex(32) }
    end

    trait :github do
      provider { "github" }
      uid { generate(:github_uid) }
      oauth_token { SecureRandom.hex(32) }
    end

    trait :verified do
      verified_at { Time.current }
    end
  end
end

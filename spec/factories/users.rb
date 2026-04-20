FactoryBot.define do
  factory :user do
    email_address { Faker::Internet.email }
    password { "SecureP@ssw0rd123!" }
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }

    trait :with_email_auth do
      after(:create) do |user|
        user.authentications.find_or_create_by!(provider: "email") do |auth|
          auth.uid = user.email_address
        end
      end
    end

    trait :with_avatar do
      after(:create) do |user|
        fixture = Rails.root.join("spec/fixtures/files/avatar.png")
        user.avatar.attach(io: File.open(fixture), filename: "avatar.png", content_type: "image/png")
        user.avatar_original.attach(io: File.open(fixture), filename: "original.png", content_type: "image/png")
        user.update!(avatar_source: "upload")
      end
    end
  end
end

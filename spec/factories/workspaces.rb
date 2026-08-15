FactoryBot.define do
  factory :workspace do
    name { Faker::Company.name }
    plan { "free" }

    trait :with_logo do
      after(:create) do |workspace|
        fixture = Rails.root.join("spec/fixtures/files/avatar.png")
        workspace.logo.attach(io: File.open(fixture), filename: "logo.png", content_type: "image/png")
        workspace.logo_original.attach(io: File.open(fixture), filename: "logo-original.png", content_type: "image/png")
        workspace.update!(logo_source: "upload")
      end
    end
  end
end

FactoryBot.define do
  factory :room_gallery_image do
    room
    workspace { room.workspace }
    sequence(:position, &:itself)
    image_alt { "Gallery photo" }

    after(:build) do |image|
      image.image.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "gallery.png",
        content_type: "image/png"
      )
    end

    trait :needs_alt do
      image_alt { nil }
      image_derived_ok { false }
    end
  end
end

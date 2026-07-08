FactoryBot.define do
  factory :room_gallery_image do
    room
    workspace { room.workspace }
    sequence(:position, &:itself)

    after(:build) do |image|
      image.image.attach(
        io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
        filename: "gallery.png",
        content_type: "image/png"
      )
    end
  end
end

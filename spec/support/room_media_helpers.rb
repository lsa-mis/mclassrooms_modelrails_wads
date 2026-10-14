module RoomMediaHelpers
  def attach_panorama!(room)
    room.panorama.attach(io: File.open(Rails.root.join("spec/fixtures/files/room.jpg")),
                         filename: "pano.jpg", content_type: "image/jpeg")
  end
end

RSpec.configure do |config|
  config.include RoomMediaHelpers, type: :request
end

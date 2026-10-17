module RoomEditPage
  extend ActiveSupport::Concern

  private

  def prepare_edit_page(open_media: nil, display_room: @room)
    build_blank_gallery
    @display_room = display_room
    @presenter = RoomPresenter.new(display_room, url: room_url(display_room))
    @open_media = open_media
  end

  def render_edit_failure(open_media)
    prepare_edit_page(open_media: open_media, display_room: Room.for_current_workspace.find(@room.id))
    render "rooms/edit", status: :unprocessable_content
  end

  def build_blank_gallery
    remaining = 5 - @room.gallery.size
    if remaining.positive?
      next_position = (@room.gallery.map(&:position).compact.max || 0) + 1
      remaining.times { |i| @room.gallery.build(position: next_position + i) }
    end

    preload_gallery_image_attachments
  end

  def preload_gallery_image_attachments(replaced_ids: [])
    persisted = @room.gallery.select(&:persisted?)
    return if persisted.empty?

    ActiveRecord::Associations::Preloader.new(
      records: persisted, associations: { image_attachment: :blob }
    ).call

    replaced = persisted.select { |image| replaced_ids.include?(image.id.to_s) }
    ActiveRecord::Associations::Preloader.new(records: replaced, associations: :image_blob).call if replaced.any?
  end
end

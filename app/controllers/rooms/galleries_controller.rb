class Rooms::GalleriesController < Rooms::MediaController
  GALLERY_ROW = [ :id, :image, :position, :image_alt, :image_description ].freeze

  def update
    authorize @room, :manage_media?
    attrs = params.expect(room: [ gallery_attributes: [ GALLERY_ROW ] ]).to_h

    if stale_gallery_ids?(attrs)
      @room.errors.add(:base, t("rooms.edit.stale_gallery"))
      return render_edit_failure(:gallery)
    end

    preload_gallery_image_attachments(replaced_ids: replaced_gallery_ids(attrs))
    save_media(:gallery, attrs, notice: t("rooms.edit.gallery_saved"))
  end

  private

  def stale_gallery_ids?(attrs)
    submitted_ids = submitted_gallery_rows(attrs).map { |row| row[:id].to_s }.compact_blank
    return false if submitted_ids.empty?

    known_ids = @room.gallery_ids.map(&:to_s)
    submitted_ids.any? { |id| known_ids.exclude?(id) }
  end

  def replaced_gallery_ids(attrs)
    submitted_gallery_rows(attrs).select { |row| row[:id].present? && row[:image].present? }.map { |row| row[:id].to_s }
  end
end

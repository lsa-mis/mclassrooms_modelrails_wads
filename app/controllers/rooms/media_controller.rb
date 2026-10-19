class Rooms::MediaController < ApplicationController
  include RoomScoped
  include PublicDirectoryChrome
  include RoomEditPage

  METADATA_TEXT_KEYS = %w[panorama_alt panorama_description seating_chart_alt seating_chart_description].freeze

  private

  def save_media(slot, attrs, **success)
    if media_change?(attrs)
      result = Curation::Apply.call(record: @room, actor: Current.user, action: "room.media_updated", attributes: attrs)
      return render_saved_media_failure(slot, result) unless result.success?
    end

    @saved_media = slot
    respond_to do |format|
      format.turbo_stream do
        @room = Room.for_current_workspace.find(@room.id)
        prepare_edit_page
        render "rooms/media/update"
      end
      format.html { redirect_to edit_room_path(@room), **success }
    end
  end

  def render_saved_media_failure(slot, result)
    @room = result.payload[:record] || @room
    render_edit_failure(slot)
  end

  def remove_media(editor:, attributes: {}, **success, &removal)
    result = Curation::Apply.call(record: @room, actor: Current.user, action: "room.media_updated",
                                  attributes: attributes, &removal)
    if result.success?
      redirect_to edit_room_path(@room, open: editor), **success
    else
      redirect_to edit_room_path(@room, open: editor), alert: result.errors.to_sentence
    end
  end

  def media_change?(attrs)
    attrs = attrs.with_indifferent_access

    return true if %w[panorama seating_chart].any? { |key| attrs[key].present? }
    return true if METADATA_TEXT_KEYS.any? { |key| attrs.key?(key) && attrs[key].to_s != @room.public_send(key).to_s }

    submitted_gallery_rows(attrs).any? { |row| gallery_row_changed?(row) }
  end

  def gallery_row_changed?(row)
    return row[:image].present? if row[:id].blank?

    existing = @room.gallery.detect { |image| image.id.to_s == row[:id].to_s }
    return false if existing.blank?

    return true if row[:image].present?
    return true if row[:position].present? && existing.position.to_s != row[:position].to_s
    return true if row.key?(:image_alt) && row[:image_alt].to_s != existing.image_alt.to_s
    return true if row.key?(:image_description) && row[:image_description].to_s != existing.image_description.to_s

    false
  end

  def submitted_gallery_rows(attrs)
    rows = attrs.with_indifferent_access[:gallery_attributes]
    return [] if rows.blank?

    rows = rows.is_a?(Hash) ? rows.values : Array(rows)
    rows.map(&:with_indifferent_access)
  end
end

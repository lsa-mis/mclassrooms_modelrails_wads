class Rooms::MediaController < ApplicationController
  include RoomScoped

  private

  def remove_media(editor:, attributes: {}, **success, &removal)
    result = Curation::Apply.call(record: @room, actor: Current.user, action: "room.media_updated",
                                  attributes: attributes, &removal)
    if result.success?
      redirect_to edit_room_path(@room, open: editor), **success
    else
      redirect_to edit_room_path(@room, open: editor), alert: result.errors.to_sentence
    end
  end
end

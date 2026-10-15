class Rooms::PhotosController < Rooms::MediaController
  def destroy
    authorize @room, :manage_media?
    photo = @room.gallery.find(params[:id])
    row = @room.gallery_by_position.index(photo) + 1
    remove_media(editor: "gallery", notice: t("rooms.edit.photo_removed", position: row)) { photo.destroy! }
  end
end

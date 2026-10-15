class Rooms::PhotosController < Rooms::MediaController
  def destroy
    authorize @room, :manage_media?
    photo = @room.gallery.find(params[:id])
    remove_media(editor: "gallery", notice: t("rooms.edit.photo_removed", position: photo.position)) { photo.destroy! }
  end
end

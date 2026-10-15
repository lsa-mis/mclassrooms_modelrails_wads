class Rooms::PanoramasController < Rooms::MediaController
  def destroy
    authorize @room, :manage_media?
    remove_media(editor: "panorama", notice: t("rooms.edit.panorama_removed"), attributes: { remove_panorama: "1" })
  end
end

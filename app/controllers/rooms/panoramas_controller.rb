class Rooms::PanoramasController < Rooms::MediaController
  def update
    authorize @room, :manage_media?
    attrs = params.expect(room: [ :panorama, :panorama_alt, :panorama_description ]).to_h
    save_media(:panorama, attrs, notice: t("rooms.edit.panorama_saved"))
  end

  def destroy
    authorize @room, :manage_media?
    remove_media(editor: "panorama", notice: t("rooms.edit.panorama_removed"), attributes: { remove_panorama: "1" })
  end
end

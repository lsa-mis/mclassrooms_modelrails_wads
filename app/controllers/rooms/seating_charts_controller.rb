class Rooms::SeatingChartsController < Rooms::MediaController
  def destroy
    authorize @room, :manage_media?
    remove_media(editor: "seating_chart", notice: t("rooms.edit.seating_chart_removed"),
                 attributes: { remove_seating_chart: "1" })
  end
end

class Rooms::SeatingChartsController < Rooms::MediaController
  def update
    authorize @room, :manage_media?
    attrs = params.expect(room: [ :seating_chart, :seating_chart_alt, :seating_chart_description ]).to_h
    save_media(:seating_chart, attrs, notice: t("rooms.edit.seating_chart_saved"))
  end

  def destroy
    authorize @room, :manage_media?
    remove_media(editor: "seating_chart", notice: t("rooms.edit.seating_chart_removed"),
                 attributes: { remove_seating_chart: "1" })
  end
end

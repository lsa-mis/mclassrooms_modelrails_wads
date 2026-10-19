class Rooms::HidingsController < ApplicationController
  include RoomScoped
  include RoomEditPage

  def create
    authorize @room, :hide?
    @room.hide!(actor: Current.user)
    respond_with_visibility(notice: t("rooms.hide.success"))
  end

  def destroy
    authorize @room, :unhide?
    @room.unhide!(actor: Current.user)
    respond_with_visibility(notice: t("rooms.unhide.success"))
  end

  private

  def respond_with_visibility(**success)
    return redirect_to(find_a_room_path, **success) unless policy(@room).edit?

    respond_to do |format|
      format.turbo_stream { prepare_edit_page }
      format.html { redirect_to edit_room_path(@room), **success }
    end
  end
end

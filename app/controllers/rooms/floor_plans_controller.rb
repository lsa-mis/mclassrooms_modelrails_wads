class Rooms::FloorPlansController < ApplicationController
  include RoomScoped
  include PublicDirectoryChrome

  before_action :redirect_hidden_room_for_non_admins

  def show
    authorize @room, :show?
    @floor = @room.floor
    return redirect_to(room_path(@room), notice: t("rooms.floor_plan.no_floor")) if @floor.nil?

    @rooms_on_floor = Room.for_current_workspace.classroom.listed
                          .where(floor_id: @floor.id).natural_room_order
  end

  private

  def redirect_hidden_room_for_non_admins
    return unless @room.hidden?
    return if current_grant.admin?

    redirect_to find_a_room_path, notice: t("rooms.inactive_notice")
  end
end

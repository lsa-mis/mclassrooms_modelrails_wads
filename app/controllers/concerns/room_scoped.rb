module RoomScoped
  extend ActiveSupport::Concern

  included do
    include DirectoryScoped
    before_action :set_room
  end

  private

  def set_room
    @room = Room.for_current_workspace.find_by!(rmrecnbr: params[:room_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to find_a_room_path, alert: t("rooms.show.not_found")
  end
end

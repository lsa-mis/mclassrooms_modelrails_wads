# Saved rooms (shortlist): create/destroy the signed-in user's bookmark on a
# room. The room resolves through RoomPolicy::Scope (never a bare find —
# CLAUDE.md deviation #1's invariant), so hidden/foreign rooms 404 before any
# write. create_or_find_by leans on the composite unique index: a
# double-click race resolves to the winner's row instead of raising.
class SavedRoomsController < ApplicationController
  include DirectoryScoped

  def create
    authorize SavedRoom
    room = RoomPolicy::Scope.new(pundit_user, Room).resolve.find(params[:room_id])
    @saved = SavedRoom.create_or_find_by(user: Current.user, room: room, workspace: room.workspace)
    @room = room
    respond_toggle
  end

  def destroy
    @saved = Current.user.saved_rooms.find(params[:id])
    authorize @saved
    @room = @saved.room
    @saved.destroy!
    @saved = nil
    respond_toggle
  end

  private

  # Both templates re-render the toggle and the header count; the count
  # element only exists on the index, where Turbo ignores updates to a
  # missing target on the room page.
  def respond_toggle
    @saved_count = Current.user.saved_rooms.where(workspace: Current.workspace).count
    respond_to do |format|
      format.turbo_stream { render :toggle }
      format.html { redirect_back fallback_location: room_path(@room) }
    end
  end
end

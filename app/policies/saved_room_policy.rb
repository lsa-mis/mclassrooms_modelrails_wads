# Saved rooms are personal shortlist entries: any signed-in member may save
# (the ROOM's visibility is enforced separately — the controller resolves it
# through RoomPolicy::Scope, so an unseeable room can never be saved), and
# only the owner may unsave their own row.
class SavedRoomPolicy < DirectoryPolicy
  def create?  = user.present?
  def destroy? = record.user_id == user&.id
end

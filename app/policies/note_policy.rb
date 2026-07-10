# MiClassrooms Phase 5 Task 4 (Brief §14.1): editors author notes on their
# own units' rooms; notes on buildings stay admin-only (interpretation 2 —
# buildings span units, so there's no single unit's editor to hand building
# authorship to). Replies inherit the rule through the shared `notable`
# (a reply's notable is always the same record as its parent's, per
# Note#parent_must_be_root), so no separate reply-authorship check is
# needed.
class NotePolicy < DirectoryPolicy
  def create?  = writable?
  def update?  = writable?
  def destroy? = writable?

  private

  # §14.1 matrix: editors author notes on their units' ROOMS. Notes on
  # BUILDINGS are admin-only — building-level actions (including building
  # notes) stay with admins because buildings span units (interpretation 2).
  # Replies inherit the rule through the shared notable. Editors cannot
  # touch notes on rooms they cannot see (hidden / no unit).
  def writable?
    return true if grant.admin?
    notable = record.notable
    notable.is_a?(Room) && grant.can_edit_room?(notable) &&
      notable.in_feed? && !notable.hidden?
  end
end

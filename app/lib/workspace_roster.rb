# The rows of a workspace's members page: pending invitations first (they are
# actionable), then memberships (settled), each group honoring the active
# sort within itself (#124 — the sort headers render over the combined table,
# so a control that applied to half the rows would lie).
#
# Search and sort run in Ruby over rows the two `for_members_index` scopes
# already load, not in SQL: the columns they read — names and email
# addresses — are personal data that the encryption step of #902 makes
# unsearchable and unsortable at the database. Every matching row of both
# kinds is materialized here; at template scale that is tens of rows, and
# #904 holds the trigger for the day a workspace outgrows it.
class WorkspaceRoster
  def initialize(workspace)
    @workspace = workspace
  end

  def rows(q: nil, role: nil, status: nil, sort: nil, direction: nil)
    invitations = @workspace.invitations.for_members_index(role: role, status: status)
    memberships = @workspace.memberships.for_members_index(role: role, status: status)

    arrange(invitations, q, sort, direction, text: INVITATION_TEXT, keys: INVITATION_SORT_KEYS) +
      arrange(memberships, q, sort, direction, text: MEMBERSHIP_TEXT, keys: MEMBERSHIP_SORT_KEYS)
  end

  private

  MEMBERSHIP_TEXT = ->(m) { [ m.user.first_name, m.user.last_name, m.user.email_address ] }
  # An invitation has no name yet, so its email is what the name column sorts
  # by — the same value the user sees in that row.
  INVITATION_TEXT = ->(i) { [ i.email ] }

  MEMBERSHIP_SORT_KEYS = {
    "name"  => ->(m) { [ m.user.first_name.to_s.downcase, m.user.last_name.to_s.downcase ] },
    "email" => ->(m) { m.user.email_address.to_s.downcase },
    "role"  => ->(m) { m.role.name.to_s.downcase }
  }.freeze

  INVITATION_SORT_KEYS = {
    "name"  => ->(i) { i.email.to_s.downcase },
    "email" => ->(i) { i.email.to_s.downcase },
    "role"  => ->(i) { i.role.name.to_s.downcase }
  }.freeze

  def arrange(rows, query, column, direction, text:, keys:)
    matching = matching(rows.to_a, query, text)
    key = keys[column.to_s]
    return matching.sort_by { |row| [ row.created_at, row.id ] }.reverse unless key

    sorted = matching.sort_by { |row| [ key.call(row), row.id ] }
    direction.to_s.downcase == "asc" ? sorted : sorted.reverse
  end

  # Plain substring match, case-insensitive. A query is text, never a
  # pattern: "a_b" matches "a_b@…" and not "axb@…" (#454).
  def matching(rows, query, text)
    return rows if query.blank?

    needle = query.to_s.downcase
    rows.select { |row| text.call(row).any? { |value| value.to_s.downcase.include?(needle) } }
  end
end

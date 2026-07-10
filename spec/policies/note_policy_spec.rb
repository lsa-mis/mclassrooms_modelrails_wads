require "rails_helper"

# MiClassrooms Phase 5 Task 4 (Brief §14.1): NotePolicy — editors author
# notes on their own units' VISIBLE rooms only; notes on rooms outside their
# unit, rooms with no unit at all, hidden rooms, and BUILDINGS (interpretation
# 2 — buildings span units, so no single unit's editor owns building
# authorship) are all admin-only. Replies inherit the rule through the
# shared `notable` (Note#parent_must_be_root pins a reply to its parent's
# notable), verified below.
RSpec.describe NotePolicy do
  include_context "role matrix"

  let(:note_on_room_in_unit)        { create(:note, notable: room_in_unit) }
  let(:note_on_room_no_unit)        { create(:note, notable: room_no_unit) }
  let(:note_on_hidden_room_in_unit) { create(:note, notable: hidden_room_in_unit) }
  let(:note_on_building)            { create(:note, notable: building) }

  # Brief §14.1 (Task 4 table). Columns: admin, editor-in-unit,
  # editor-other-unit, viewer.
  MATRIX = [
    [ :create?,  :note_on_room_in_unit,        true, true,  false, false ],
    [ :update?,  :note_on_room_in_unit,        true, true,  false, false ],
    [ :destroy?, :note_on_room_in_unit,        true, true,  false, false ],
    [ :create?,  :note_on_room_no_unit,        true, false, false, false ],
    [ :update?,  :note_on_room_no_unit,        true, false, false, false ],
    [ :destroy?, :note_on_room_no_unit,        true, false, false, false ],
    [ :create?,  :note_on_hidden_room_in_unit, true, false, false, false ],
    [ :update?,  :note_on_hidden_room_in_unit, true, false, false, false ],
    [ :destroy?, :note_on_hidden_room_in_unit, true, false, false, false ],
    [ :create?,  :note_on_building,            true, false, false, false ],
    [ :update?,  :note_on_building,            true, false, false, false ],
    [ :destroy?, :note_on_building,            true, false, false, false ]
  ].freeze

  USERS = %i[admin_user editor_user other_editor_user viewer_user].freeze

  MATRIX.each do |action, record_name, *expected|
    USERS.each_with_index do |user_name, i|
      it "#{action} on #{record_name} is #{expected[i]} for #{user_name}" do
        policy = described_class.new(send(user_name), send(record_name))
        expect(policy.public_send(action)).to be expected[i]
      end
    end
  end

  # Replies don't carry their own notable independent of the parent — they
  # inherit it (Note#parent_must_be_root only allows a reply whose parent is
  # itself a root note; both share the same `notable`). Pinned here so a
  # reply's authorization doesn't silently diverge from its root note's.
  describe "a reply inherits its parent's notable" do
    let(:parent_note) { create(:note, notable: room_in_unit) }
    let(:reply) { create(:note, notable: room_in_unit, parent: parent_note) }

    it "grants the same create?/update?/destroy? as the parent's notable would, for the in-unit editor" do
      policy = described_class.new(editor_user, reply)

      expect(policy.create?).to be true
      expect(policy.update?).to be true
      expect(policy.destroy?).to be true
    end

    it "denies the other-unit editor exactly like the parent's notable would" do
      policy = described_class.new(other_editor_user, reply)

      expect(policy.create?).to be false
    end
  end
end

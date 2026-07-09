require "rails_helper"

# MiClassrooms Phase 4 Task 1 (spec D13, Brief §14.1): Curation::Apply is the
# transactional audited-mutation entry point every admin mutation in phases 4
# and 5 flows through — room/building updates, floor-plan attach, bulk-upload
# commit, role grants. Phase 5 Task 2 only verifies this contract; the four
# examples below are the shared reference spec both phases hold to, copied
# verbatim from planning/plans/phase-5-curation-roles.md Task 2.
RSpec.describe Curation::Apply do
  let(:workspace) { create(:workspace) }
  let(:actor) { create(:user) }
  let(:room) { create(:room, nickname: "Old") }

  before { Current.workspace = workspace }

  it "applies the change and writes the audit row with a before_after payload" do
    result = described_class.call(record: room, actor: actor, action: "room.updated",
                                  attributes: { nickname: "Aud 3" })
    expect(result).to be_success
    log = result.payload[:activity_log]
    expect(log.actor).to eq(actor)
    expect(log.before_after).to eq(
      "before" => { "nickname" => "Old" }, "after" => { "nickname" => "Aud 3" }
    )
  end

  it "rolls back the audit row when the record write fails" do
    allow(room).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(room))
    # `actor` (a User) onboards a personal workspace + owner Membership on
    # creation (default :personal tenancy posture) — both Trackable, so
    # lazily creating `actor` for the first time inside the `expect` block
    # below would add its own incidental ActivityLog rows to the count this
    # assertion is trying to isolate to Curation::Apply. Forcing it here,
    # alongside the `room` stub above, keeps the measured delta scoped to
    # the call under test.
    actor
    expect {
      result = described_class.call(record: room, actor: actor, action: "room.updated",
                                    attributes: { nickname: "X" })
      expect(result).not_to be_success
    }.not_to change(ActivityLog, :count)
  end

  it "rolls back the record change when the audit write fails" do
    allow(ActivityLog).to receive(:create!)
      .and_raise(ActiveRecord::RecordInvalid.new(ActivityLog.new))
    result = described_class.call(record: room, actor: actor, action: "room.updated",
                                  attributes: { nickname: "X" })
    expect(result).not_to be_success
    expect(room.reload.nickname).to eq("Old")
  end

  it "supports a block for destroys and snapshots the full record as 'before'" do
    note = create(:note)
    result = described_class.call(record: note, actor: actor, action: "note.destroyed") { |r| r.destroy! }
    expect(note).to be_destroyed
    expect(result.payload[:activity_log].before_after["after"]).to be_nil
  end

  # Phase-4-brief addition (a): a genuine model validation failure — not a
  # stubbed exception — must surface as Result.failure with the model's own
  # error messages, and must not write an ActivityLog. Room#rmrecnbr is
  # `presence: true, uniqueness: true`, so nilling it fails save! for real.
  it "returns a failure with model errors and writes no ActivityLog on a validation failure" do
    # Force room/actor materialization before measuring — see the note above
    # test 2 on why an unforced `actor` first-reference inside the counting
    # block would pollute the delta with its own onboarding ActivityLog rows.
    room
    actor
    expect {
      result = described_class.call(record: room, actor: actor, action: "room.updated",
                                    attributes: { rmrecnbr: nil })
      expect(result).not_to be_success
      expect(result.errors).to include(a_string_matching(/Rmrecnbr/i))
    }.not_to change(ActivityLog, :count)
  end

  # Phase-4-brief addition (b): attachment assignment (has_one_attached) is
  # not a dirty-tracked column attribute, so `record.changes` never sees it —
  # the reference implementation's diff is genuinely empty for a pure
  # attachment assignment ({"before" => {}, "after" => {}}). That emptiness
  # IS the safety property: there is no path through Curation::Apply that can
  # place blob bytes, base64, or raw file content into before_after, because
  # attachments never enter `diff` in the first place. Assert both the
  # observed empty shape and, defensively, that the persisted column contains
  # none of the fixture's raw bytes.
  it "does not record blob bytes when assigning an attachment" do
    fixture = Rails.root.join("spec/fixtures/files/avatar.png")
    blob = ActiveStorage::Blob.create_and_upload!(
      io: File.open(fixture), filename: "avatar.png", content_type: "image/png"
    )

    result = described_class.call(record: room, actor: actor, action: "room.photo_attached",
                                  attributes: { photo: blob })

    expect(result).to be_success
    expect(room.photo).to be_attached
    before_after = result.payload[:activity_log].before_after
    expect(before_after).to eq("before" => {}, "after" => {})

    raw_bytes = File.binread(fixture)
    expect(before_after.to_json).not_to include(raw_bytes)
    expect(before_after.to_json).not_to include(Base64.strict_encode64(raw_bytes))
  end

  # Phase-5 Task 2's final checkbox (interpretation 5, roadmap D13 note):
  # Curation::Apply is the sole audit writer for these models — none of them
  # may also include Trackable, or every mutation would double-log.
  it "keeps every curation model free of Trackable (Apply is their sole audit writer)" do
    curation_models = [ Room, Building, Note, Announcement, EditorAssignment, Floor, RoomGalleryImage ]
    tracked = curation_models.select { |klass| klass.include?(Trackable) }
    expect(tracked).to be_empty
  end
end

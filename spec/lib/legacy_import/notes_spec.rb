require "rails_helper"

RSpec.describe LegacyImport::Notes do
  include_context "legacy export"

  let(:workspace) { create(:workspace, personal: false) }
  let(:actor) { create(:user) }
  let(:building) { create(:building, workspace:, bldrecnbr: "1005058") }
  let!(:room) { create(:room, building:, rmrecnbr: "2031968") }

  def note_row(legacy_id, **attrs)
    { legacy_id:, parent_legacy_id: nil, notable_type: "Room", notable_key: "2031968",
      author_email: "dcran@umich.edu", alert: false, body_html: "<div>Call (734) 615-0100</div>",
      created_at: "2022-02-24T19:01:26Z", updated_at: "2022-07-11T15:50:22Z" }.merge(attrs)
  end

  it "creates a note credited to the import account, with attribution and the legacy dates" do
    export_tree.row(:notes, note_row(1, alert: true))

    run_importer

    note = Note.sole
    expect(note).to have_attributes(notable: room, author: actor, alert: true, parent: nil,
                                    created_at: Time.iso8601("2022-02-24T19:01:26Z"),
                                    updated_at: Time.iso8601("2022-07-11T15:50:22Z"))
    expect(note.body.to_plain_text).to include("Call (734) 615-0100", "Originally posted by dcran@umich.edu on Feb 24, 2022.")
  end

  it "resolves a building note by bldrecnbr" do
    export_tree.row(:notes, note_row(2, notable_type: "Building", notable_key: "1005058"))

    run_importer

    expect(Note.sole.notable).to eq(building)
  end

  it "threads a reply under its imported parent and reports an orphan" do
    export_tree.row(:notes, note_row(1))
               .row(:notes, note_row(2, parent_legacy_id: 1, created_at: "2022-03-01T10:00:00Z"))
               .row(:notes, note_row(3, parent_legacy_id: 99, created_at: "2022-03-02T10:00:00Z"))

    result = run_importer

    parent = Note.find_by(parent_id: nil)
    expect(Note.where(parent:).count).to eq(1)
    expect(result.payload[:unmatched_lines]).to eq([ "Note\t3\tparent 99 not imported" ])
  end

  it "skips notes it already imported" do
    export_tree.row(:notes, note_row(1))
    run_importer

    result = nil
    expect { result = run_importer }.not_to change(Note, :count)

    expect(result.payload[:counters]).to include(skipped: 1, created: 0)
  end

  it "reports a note whose room is not in this workspace" do
    export_tree.row(:notes, note_row(1, notable_key: "9999999"))

    expect(run_importer.payload[:unmatched_lines]).to eq([ "Note\t1\tRoom 9999999" ])
  end

  # The ordinary note at the end is the control: without it, this example
  # would pass just as well if commit callbacks never fired at all.
  it "does not broadcast while importing, though an ordinary note does" do
    allow(Turbo::StreamsChannel).to receive(:broadcast_prepend_to)
    export_tree.row(:notes, note_row(1))

    run_importer

    expect(Note.count).to eq(1)
    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_prepend_to)
    create(:note, notable: room, workspace:)
    expect(Turbo::StreamsChannel).to have_received(:broadcast_prepend_to)
  end

  it "writes nothing on dry run, even before the import account exists" do
    export_tree.row(:notes, note_row(1))

    result = nil
    expect { result = run_importer(dry_run: true, actor: LegacyImport::Account.build) }.not_to change(Note, :count)

    expect(result.payload[:counters]).to include(created: 1)
  end
end

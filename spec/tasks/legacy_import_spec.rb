require "rails_helper"

# House pattern for rake specs — see spec/tasks/flat_panoramas_rake_spec.rb.
RSpec.describe "legacy:import" do
  include_context "legacy export"

  let(:workspace) { create(:workspace, slug: "legacy-rake", personal: false) }
  let!(:room) { create(:room, building: create(:building, workspace:), rmrecnbr: "2196067") }

  before(:all) { RakeTasks.load_once }
  before do
    Rake::Task["legacy:import"].reenable
    export_tree.media(model: "Room", record_id: 2_196_067, attachment_name: "room_panorama", fixture: "room.jpg")
    export_tree.write!
  end

  around do |example|
    keys = %w[EXPORT WORKSPACE DRY_RUN ONLY REPORT_DIR]
    saved = ENV.to_h.slice(*keys)
    Dir.mktmpdir("legacy-report") do |dir|
      @report_dir = dir
      example.run
    end
  ensure
    keys.each { |key| ENV.delete(key) }
    saved.each { |key, value| ENV[key] = value }
  end

  def run(**env)
    env.each { |key, value| ENV[key.to_s] = value.to_s }
    captured = StringIO.new
    original = $stdout
    $stdout = captured
    Rake::Task["legacy:import"].invoke
    captured.string
  ensure
    $stdout = original
  end

  it "imports, prints the table and writes the report files" do
    output = run(EXPORT: @legacy_export_root, WORKSPACE: "legacy-rake", REPORT_DIR: @report_dir)

    expect(room.reload.panorama).to be_attached
    expect(output).to include("RoomMedia", "gallery positions:")
    expect(Dir.children(@report_dir)).to contain_exactly("unmatched.txt", "replaced.txt", "errors.txt", "summary.json")
    expect(JSON.parse(File.read(File.join(@report_dir, "summary.json")))).to include("success" => true)
  end

  it "resolves a relative EXPORT path" do
    Dir.chdir(File.dirname(@legacy_export_root)) do
      run(EXPORT: File.basename(@legacy_export_root), WORKSPACE: "legacy-rake", REPORT_DIR: @report_dir)
    end

    expect(room.reload.panorama).to be_attached
  end

  it "writes nothing on DRY_RUN" do
    expect { run(EXPORT: @legacy_export_root, WORKSPACE: "legacy-rake", REPORT_DIR: @report_dir, DRY_RUN: "1") }
      .not_to change(ActiveStorage::Attachment, :count)
  end

  it "requires EXPORT" do
    expect { run(WORKSPACE: "legacy-rake") }.to raise_error(SystemExit, /EXPORT=.* is required/)
  end

  it "requires a known WORKSPACE" do
    expect { run(EXPORT: @legacy_export_root, WORKSPACE: "nope") }.to raise_error(SystemExit, /No kept workspace found for WORKSPACE="nope"/)
  end

  it "exits non-zero when the import fails" do
    expect { run(EXPORT: @legacy_export_root, WORKSPACE: "legacy-rake", REPORT_DIR: @report_dir, ONLY: "note") }
      .to raise_error(SystemExit, /legacy:import failed: unknown phase/)
  end
end

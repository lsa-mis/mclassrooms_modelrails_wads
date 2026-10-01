# spec/lib/legacy_import/announcements_spec.rb
require "rails_helper"

RSpec.describe LegacyImport::Announcements do
  include_context "legacy export"

  let(:workspace) { create(:workspace, personal: false) }
  let(:actor) { nil }

  it "creates announcements with their rich-text body and skips empty ones" do
    export_tree.row(:announcements, slot: "home_page", body_html: "<p>Welcome back</p>")
               .row(:announcements, slot: "find_a_room_page", body_html: "")

    result = run_importer

    expect(Announcement.for("home_page").body.to_plain_text).to eq("Welcome back")
    expect(Announcement.for("find_a_room_page")).to be_nil
    expect(result.payload[:counters]).to include(created: 1, skipped: 1)
  end

  it "keeps an announcement already written in the new app" do
    create(:announcement, workspace:, slot: "about_page", body: "Current copy")
    export_tree.row(:announcements, slot: "about_page", body_html: "<p>Legacy copy</p>")

    run_importer

    expect(Announcement.for("about_page").body.to_plain_text).to eq("Current copy")
  end

  it "reports a slot the new app doesn't have" do
    export_tree.row(:announcements, slot: "sidebar", body_html: "<p>x</p>")

    expect(run_importer.payload[:unmatched_lines]).to eq([ "Announcement\tsidebar" ])
  end

  it "writes nothing on dry run" do
    export_tree.row(:announcements, slot: "home_page", body_html: "<p>Welcome back</p>")

    expect { run_importer(dry_run: true) }.not_to change(Announcement, :count)
  end
end

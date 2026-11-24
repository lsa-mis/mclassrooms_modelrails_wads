require "rails_helper"
require "kamal"

RSpec.describe "Rails 8.2 notes for forks" do
  it "tells forks the test environment shuffles unordered queries, as it does" do
    expect(Rails.root.join("config/environments/test.rb").read).to match(/^\s*config\.active_record\.shuffle_unordered_selects = true$/)
    expect(Rails.root.join("app/docs/developer/testing.md").read).to include("### Unordered queries come back shuffled", "shuffle_unordered_selects")
  end

  it "gives a deployment the backfill's dry run in a form Kamal parses" do
    guide = Rails.root.join("app/docs/developer/getting-started.md").read
    line = guide[/^bin\/kamal app exec .*action_text:clear_filename_alts.*--env.*$/]
    expect(line).to be_present

    parser = Thor::Options.new(Kamal::Cli::App.commands.fetch("exec").options)
    parsed = parser.parse(Shellwords.split(line).drop(3))

    expect(parsed["env"]).to eq("DRY_RUN" => "1")
    expect(parser.remaining).to eq([ "bin/rails action_text:clear_filename_alts" ])
  end
end

require_relative "../../lib/change_lanes"

RSpec.describe "Change lanes select every spec that reads their files" do
  let(:root) { File.expand_path("../..", __dir__) }
  let(:lanes_own_specs) { [ "spec/lib/change_lanes_spec.rb", "spec/bin/test_plan_spec.rb", "spec/code_smells/change_lane_specs_are_complete_spec.rb" ] }

  {
    locale: [ "config/locales/en.yml", /config\/locales|I18n::Tasks/ ],
    workflows: [ ".github/workflows/deploy.yml", /\.github\/|lefthook\.yml/ ],
    docs: [ "app/docs/developer/testing.md", /app\/docs/ ]
  }.each do |lane, (sample_path, reads_lane)|
    it "the #{lane} lane runs every spec whose source names its files" do
      selected = ChangeLanes.specs_for(ChangeLanes.classify([ sample_path ]), root:)
      readers = Dir.glob("spec/**/*_spec.rb", base: root).select { |spec| File.read(File.join(root, spec)).match?(reads_lane) }

      missing = (readers - lanes_own_specs - selected).sort

      expect(missing).to be_empty,
        "add these to the #{lane} lane's specs in lib/change_lanes.rb:\n  #{missing.join("\n  ")}"
    end
  end
end

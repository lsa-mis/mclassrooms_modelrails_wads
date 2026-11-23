require "tmpdir"
require "fileutils"
require_relative "../../lib/change_lanes"

RSpec.describe ChangeLanes do
  describe ".classify" do
    it "puts a locale file in the locale lane" do
      expect(described_class.classify([ "config/locales/en/brand.en.yml" ]))
        .to eq(ChangeLanes::Plan.new(lanes: [ :locale ], full: false))
    end

    it "lists every lane a mixed change touches, sorted" do
      expect(described_class.classify([ "config/locales/en/brand.en.yml", "README.md" ]).lanes).to eq([ :docs, :locale ])
    end

    [
      "config/vocabulary.local.yml",
      "config/database.yml",
      "config/locales/en.rb",
      ".github/workflows/ci.yml",
      ".github/actions/apt-packages/action.yml",
      "mise.toml",
      "app/models/user.rb",
      "spec/models/user_spec.rb",
      "app/views/docs/show.html.erb"
    ].each do |path|
      it "runs everything for #{path}" do
        expect(described_class.classify([ path ])).to eq(ChangeLanes::Plan.new(lanes: [], full: true))
      end
    end

    it "runs everything when one path of many falls outside every lane" do
      expect(described_class.classify([ "README.md", "app/models/user.rb" ]).full).to be(true)
    end

    it "runs everything for an empty diff" do
      expect(described_class.classify([]).full).to be(true)
    end

    it "puts a workflow other than CI's own in the workflows lane" do
      expect(described_class.classify([ ".github/workflows/deploy.yml" ]).lanes).to eq([ :workflows ])
    end

    it "puts app docs and changelog fragments in the docs lane" do
      expect(described_class.classify([ "app/docs/developer/testing.md" ]).lanes).to eq([ :docs ])
      expect(described_class.classify([ "changelog.d/fix-x.md" ]).lanes).to eq([ :docs ])
    end
  end

  context "with a spec tree on disk" do
    let(:root) { Dir.mktmpdir }

    after { FileUtils.rm_rf(root) }

    def touch(*paths)
      paths.each do |path|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.write(File.join(root, path), "")
      end
    end

    describe ".specs_for" do
      it "expands the lane's spec globs to the files that exist" do
        touch("spec/i18n_spec.rb", "spec/locales/shape_spec.rb", "spec/config/vocabulary_fork_spec.rb",
              "spec/models/user_spec.rb")

        specs = described_class.specs_for(described_class.classify([ "config/locales/en.yml" ]), root:)

        expect(specs).to eq([ "spec/config/vocabulary_fork_spec.rb", "spec/i18n_spec.rb", "spec/locales/shape_spec.rb" ])
      end

      it "selects nothing for a full plan" do
        touch("spec/i18n_spec.rb")

        expect(described_class.specs_for(described_class.classify([]), root:)).to eq([])
      end
    end

    describe ".related_specs" do
      it "maps each path to its conventional spec, keeps the ones that exist, and adds the code smells" do
        touch("spec/models/user_spec.rb", "spec/requests/admin/users_spec.rb", "spec/requests/admin/users/bulk_spec.rb",
              "spec/lib/fork_config_spec.rb", "spec/bin/branch_changes_spec.rb", "spec/models/role_spec.rb",
              "spec/components/ui/badge_component_spec.rb", "spec/code_smells/a_spec.rb", "spec/code_smells/b_spec.rb")

        specs = described_class.related_specs(
          [ "app/models/user.rb", "app/controllers/admin/users_controller.rb", "lib/fork_config.rb",
            "bin/branch-changes", "spec/models/role_spec.rb", "app/components/ui/badge_component.html.erb",
            "app/models/ghost.rb" ],
          root:
        )

        expect(specs).to eq([
          "spec/bin/branch_changes_spec.rb", "spec/code_smells/a_spec.rb", "spec/code_smells/b_spec.rb",
          "spec/components/ui/badge_component_spec.rb", "spec/lib/fork_config_spec.rb",
          "spec/models/role_spec.rb", "spec/models/user_spec.rb",
          "spec/requests/admin/users/bulk_spec.rb", "spec/requests/admin/users_spec.rb"
        ])
      end
    end
  end
end

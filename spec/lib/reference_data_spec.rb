require "rails_helper"

# Exercises ReferenceData.seed! against a throwaway fixture YAML (never the
# real db/seeds/reference_data.yml — that file's dev-plausible sample content
# is not this spec's concern, only the loader's upsert semantics are).
RSpec.describe ReferenceData do
  let(:workspace) { create(:workspace) }

  def yaml_fixture(hash)
    file = Tempfile.new(%w[reference_data .yml])
    file.write(hash.to_yaml)
    file.flush
    file.path
  end

  # short_code is stored normalized (CharacteristicDisplayRule#normalize_short_code,
  # before_validation), and ReferenceData.seed! looks rows up by the raw YAML
  # short_code — so the seed value must already be in normalized form or the
  # second seed can't find its own row (idempotency breaks). These fixtures
  # therefore use normalized short_codes; the loader's upsert semantics, not
  # the normalization, are what this spec exercises.
  let(:path) do
    yaml_fixture(
      "characteristic_display_rules" => [
        { "short_code" => "instrcomp", "icon_key" => "computer", "filterable" => true }
      ],
      "unit_display_names" => [
        { "department_group" => "COLLEGE_OF_LSA", "display_name" => "College of LSA" }
      ],
      "sync_scope_rules" => [
        { "rule_type" => "campus_allow", "value" => "100" }
      ]
    )
  end

  describe ".seed!" do
    it "creates each row exactly once, even across repeated runs" do
      expect { described_class.seed!(workspace: workspace, path: path) }
        .to change(CharacteristicDisplayRule, :count).by(1)
        .and change(UnitDisplayName, :count).by(1)
        .and change(SyncScopeRule, :count).by(1)

      expect {
        described_class.seed!(workspace: workspace, path: path)
      }.not_to change {
        [ CharacteristicDisplayRule.count, UnitDisplayName.count, SyncScopeRule.count ]
      }
    end

    it "assigns every seeded row to the passed workspace" do
      described_class.seed!(workspace: workspace, path: path)

      expect(CharacteristicDisplayRule.sole.workspace).to eq(workspace)
      expect(UnitDisplayName.sole.workspace).to eq(workspace)
      expect(SyncScopeRule.sole.workspace).to eq(workspace)
    end

    it "updates a changed attribute in place on re-seed instead of duplicating the row" do
      described_class.seed!(workspace: workspace, path: path)
      record = CharacteristicDisplayRule.find_by!(short_code: "instrcomp", workspace: workspace)
      expect(record.filterable).to be(true)

      changed_path = yaml_fixture(
        "characteristic_display_rules" => [
          { "short_code" => "instrcomp", "icon_key" => "computer", "filterable" => false }
        ]
      )

      expect {
        described_class.seed!(workspace: workspace, path: changed_path)
      }.not_to change(CharacteristicDisplayRule, :count)

      expect(record.reload.filterable).to be(false)
    end

    it "scopes rows per workspace, not globally, so two workspaces can each hold their own row" do
      other_workspace = create(:workspace)

      described_class.seed!(workspace: workspace, path: path)
      described_class.seed!(workspace: other_workspace, path: path)

      expect(CharacteristicDisplayRule.count).to eq(2)
      expect(CharacteristicDisplayRule.where(workspace: workspace).count).to eq(1)
      expect(CharacteristicDisplayRule.where(workspace: other_workspace).count).to eq(1)
    end
  end
end

# Loads db/seeds/reference_data.yml (or a caller-supplied path) and
# idempotently upserts the three admin-editable reference-data models —
# CharacteristicDisplayRule, UnitDisplayName, SyncScopeRule — into the given
# workspace. Keyed on each model's natural key so re-running (dev bootstrap
# via db/seeds.rb, or the phase 8 cutover importer) updates existing rows in
# place instead of creating duplicates. See db/seeds/reference_data.yml for
# the dev-vs-production sample-data contract.
class ReferenceData
  NATURAL_KEYS = {
    "characteristic_display_rules" => %w[short_code],
    "unit_display_names" => %w[department_group],
    "sync_scope_rules" => %w[rule_type value]
  }.freeze

  MODEL_CLASSES = {
    "characteristic_display_rules" => CharacteristicDisplayRule,
    "unit_display_names" => UnitDisplayName,
    "sync_scope_rules" => SyncScopeRule
  }.freeze

  class << self
    def seed!(workspace:, path: Rails.root.join("db/seeds/reference_data.yml"))
      data = YAML.load_file(path) || {}

      data.each do |table_key, rows|
        model_class = MODEL_CLASSES.fetch(table_key) do
          raise ArgumentError, "ReferenceData: unknown reference-data key #{table_key.inspect}"
        end
        natural_key_columns = NATURAL_KEYS.fetch(table_key)

        Array(rows).each do |attrs|
          # Natural key lookup is workspace-scoped, matching each model's DB
          # unique index (workspace_id + natural key) — two workspaces can
          # each hold their own row for the same short_code/department_group/
          # rule_type+value pair without colliding.
          natural_key = attrs.slice(*natural_key_columns).merge("workspace_id" => workspace.id)
          record = model_class.find_or_initialize_by(natural_key)
          record.update!(attrs.merge("workspace" => workspace))
        end
      end
    end
  end
end

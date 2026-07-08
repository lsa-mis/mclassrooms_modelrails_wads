class CreateReferenceDataTables < ActiveRecord::Migration[8.1]
  def change
    create_table :characteristic_display_rules do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :short_code, null: false
      t.string :icon_key
      t.boolean :filterable, null: false, default: true
      t.string :category_override
      t.boolean :team_learning, null: false, default: false

      t.timestamps
    end
    add_index :characteristic_display_rules, [ :workspace_id, :short_code ],
      unique: true, name: "index_characteristic_display_rules_on_workspace_and_code"

    create_table :unit_display_names do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :department_group, null: false
      t.string :display_name, null: false

      t.timestamps
    end
    add_index :unit_display_names, [ :workspace_id, :department_group ],
      unique: true, name: "index_unit_display_names_on_workspace_and_dept_group"

    create_table :sync_scope_rules do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :rule_type, null: false
      t.string :value, null: false

      t.timestamps
    end
    add_index :sync_scope_rules, [ :workspace_id, :rule_type, :value ],
      unique: true, name: "index_sync_scope_rules_on_workspace_type_and_value"
  end
end

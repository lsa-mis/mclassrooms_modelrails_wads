class CreateCampusesAndUnits < ActiveRecord::Migration[8.1]
  def change
    create_table :campuses do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :code, null: false
      t.string :description

      t.timestamps
    end
    add_index :campuses, [ :workspace_id, :code ], unique: true, name: "index_campuses_on_workspace_and_code"

    create_table :units do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :department_group, null: false
      t.string :description

      t.timestamps
    end
    add_index :units, [ :workspace_id, :department_group ], unique: true, name: "index_units_on_workspace_and_dept_group"
  end
end

class CreateActivityLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_logs do |t|
      t.references :actor, null: true, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.references :trackable, polymorphic: true, null: false
      t.references :workspace, null: true, foreign_key: true
      t.string :visibility, null: false, default: "workspace"
      t.json :metadata, default: {}

      t.timestamps
    end

    add_index :activity_logs, [ :workspace_id, :created_at ]
  end
end

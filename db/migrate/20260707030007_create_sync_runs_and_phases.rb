class CreateSyncRunsAndPhases < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_runs do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :status, null: false, default: "running"
      t.boolean :dry_run, null: false, default: false
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    # error_messages (NOT `errors` — collides with ActiveModel::Errors and
    # raises DangerousAttributeError when Rails generates the `errors` reader).
    create_table :sync_phases do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :sync_run, null: false, foreign_key: true
      t.string :key, null: false
      t.string :status, null: false, default: "pending"
      t.json :counters, null: false, default: {}
      t.json :warnings, null: false, default: []
      t.json :error_messages, null: false, default: []
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :sync_phases, [ :sync_run_id, :key ], unique: true
  end
end

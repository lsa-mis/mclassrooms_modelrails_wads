class CreateWorkspaces < ActiveRecord::Migration[8.1]
  def change
    create_table :workspaces do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :plan, default: "free", null: false
      t.integer :max_members, default: 5, null: false
      t.integer :max_teams, default: 3, null: false
      t.string :primary_color
      t.datetime :discarded_at

      t.timestamps
    end

    add_index :workspaces, :slug, unique: true
    add_index :workspaces, :discarded_at
  end
end

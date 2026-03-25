class CreateMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true
      t.datetime :discarded_at

      t.timestamps
    end

    add_index :memberships, [:user_id, :workspace_id], unique: true
    add_index :memberships, :discarded_at
  end
end

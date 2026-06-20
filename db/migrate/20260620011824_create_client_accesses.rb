class CreateClientAccesses < ActiveRecord::Migration[8.1]
  def change
    create_table :client_accesses do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :company_name, null: false
      t.datetime :discarded_at
      t.timestamps
    end

    add_index :client_accesses, [ :project_id, :user_id ], unique: true
    add_index :client_accesses, :discarded_at
  end
end

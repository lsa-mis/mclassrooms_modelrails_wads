class CreateProjectMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :project_memberships do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "editor"
      t.boolean :pinned, default: false, null: false

      t.timestamps
    end

    add_index :project_memberships, [ :project_id, :user_id ], unique: true
  end
end

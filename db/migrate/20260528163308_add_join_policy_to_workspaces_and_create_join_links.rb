class AddJoinPolicyToWorkspacesAndCreateJoinLinks < ActiveRecord::Migration[8.1]
  # Reshape 2a: per-workspace join policy + shareable join links.
  # See docs/reshape-2-per-workspace-join-policy-spec.md and app/docs/presets.md.
  def change
    add_column :workspaces, :join_policy, :string, null: false, default: "invite"
    add_index  :workspaces, :join_policy

    create_table :workspace_join_links do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :token, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :workspace_join_links, :token, unique: true
    add_index :workspace_join_links, [ :workspace_id, :revoked_at ]
  end
end

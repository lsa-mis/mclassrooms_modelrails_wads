class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :invitations do |t|
      t.references :invitable, polymorphic: true, null: false
      t.string :email
      t.string :token, null: false
      t.references :role, null: false, foreign_key: true
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.references :accepted_by, null: true, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "pending"
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :declined_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :invitations, :token, unique: true
    add_index :invitations, [:invitable_type, :invitable_id]
    add_index :invitations, [:email, :invitable_type, :invitable_id],
              unique: true,
              where: "status = 'pending'",
              name: "index_invitations_on_email_and_invitable_pending"
  end
end

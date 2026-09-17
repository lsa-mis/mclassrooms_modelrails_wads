# frozen_string_literal: true

# A dedicated row rather than a users column, so grant/revoke carry their own
# provenance and a future scoped-operator model is an additive nullable FK on
# this table, not a column-to-rows data migration every fork absorbs.
class CreateOperatorships < ActiveRecord::Migration[8.1]
  def change
    create_table :operatorships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :granted_by, null: true, foreign_key: { to_table: :users }
      t.datetime :discarded_at
      t.timestamps
    end

    # One live operatorship per user; revoked rows stay for the audit trail.
    add_index :operatorships, :user_id,
      unique: true,
      where: "discarded_at IS NULL",
      name: "index_operatorships_on_user_id_where_kept"
    add_index :operatorships, :discarded_at
  end
end

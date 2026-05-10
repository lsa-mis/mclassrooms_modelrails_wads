class AddPartialUniqueIndexToMagicLinkTokens < ActiveRecord::Migration[8.1]
  def up
    # Consume pre-existing duplicate unconsumed tokens, keeping only the most
    # recent per email — required so the new partial unique index can be
    # created without violating its constraint on existing data.
    execute <<~SQL.squish
      UPDATE magic_link_tokens
      SET consumed_at = CURRENT_TIMESTAMP
      WHERE consumed_at IS NULL
        AND id NOT IN (
          SELECT MAX(id) FROM magic_link_tokens
          WHERE consumed_at IS NULL
          GROUP BY email
        )
    SQL

    add_index :magic_link_tokens, :email,
      unique: true,
      where: "consumed_at IS NULL",
      name: "index_magic_link_tokens_on_email_unconsumed"
  end

  def down
    remove_index :magic_link_tokens, name: "index_magic_link_tokens_on_email_unconsumed"
  end
end

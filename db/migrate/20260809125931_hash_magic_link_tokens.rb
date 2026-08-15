class HashMagicLinkTokens < ActiveRecord::Migration[8.1]
  # Inline stub so the migration never depends on the live model (which no
  # longer knows about the `token` column after this runs).
  class MigrationMagicLinkToken < ActiveRecord::Base
    self.table_name = "magic_link_tokens"
  end

  def up
    add_column :magic_link_tokens, :token_digest, :string

    # Backfill from the still-present plaintext so in-flight links keep working
    # across the deploy (SQLite has no SHA256 builtin, so digest in Ruby).
    MigrationMagicLinkToken.reset_column_information
    MigrationMagicLinkToken.where(token_digest: nil).find_each do |row|
      row.update_columns(token_digest: Digest::SHA256.hexdigest(row.token))
    end

    change_column_null :magic_link_tokens, :token_digest, false
    add_index :magic_link_tokens, :token_digest, unique: true
    remove_column :magic_link_tokens, :token # drops its unique index with it
  end

  def down
    # Irreversible in substance: a digest can't be turned back into the plaintext
    # token. Restores the column shape; existing rows become unusable (tokens are
    # short-lived, so this only affects any in-flight link).
    add_column :magic_link_tokens, :token, :string
    remove_column :magic_link_tokens, :token_digest
  end
end

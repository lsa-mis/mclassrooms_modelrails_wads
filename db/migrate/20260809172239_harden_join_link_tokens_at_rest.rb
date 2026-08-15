class HardenJoinLinkTokensAtRest < ActiveRecord::Migration[8.1]
  # Inline stubs so the migration never depends on the live models (which no
  # longer know about the plaintext columns after this runs).
  class MigrationJoinLink < ActiveRecord::Base
    self.table_name = "workspace_join_links"
  end

  class MigrationAuthentication < ActiveRecord::Base
    self.table_name = "authentications"
  end

  def up
    # --- workspace_join_links.token -> token_digest ---
    add_column :workspace_join_links, :token_digest, :string

    # Backfill from the still-present plaintext so already-shared links keep
    # working across the deploy (SQLite has no SHA256 builtin, so digest in Ruby).
    MigrationJoinLink.reset_column_information
    MigrationJoinLink.where(token_digest: nil).find_each do |row|
      row.update_columns(token_digest: Digest::SHA256.hexdigest(row.token.to_s))
    end

    change_column_null :workspace_join_links, :token_digest, false
    add_index :workspace_join_links, :token_digest, unique: true
    remove_column :workspace_join_links, :token # drops its unique index with it

    # --- authentications.pending_join_link_token -> pending_join_link_digest ---
    # Same secret, parked for the deferred-OAuth claim. Store the digest so no
    # plaintext join token survives at rest in a side table either.
    add_column :authentications, :pending_join_link_digest, :string

    MigrationAuthentication.reset_column_information
    MigrationAuthentication.where.not(pending_join_link_token: nil).find_each do |row|
      row.update_columns(pending_join_link_digest: Digest::SHA256.hexdigest(row.pending_join_link_token.to_s))
    end

    remove_column :authentications, :pending_join_link_token
  end

  def down
    # Irreversible in substance: a digest can't be turned back into the plaintext
    # token. Restores the column shape; existing digests become unusable.
    add_column :workspace_join_links, :token, :string
    remove_column :workspace_join_links, :token_digest

    add_column :authentications, :pending_join_link_token, :string
    remove_column :authentications, :pending_join_link_digest
  end
end

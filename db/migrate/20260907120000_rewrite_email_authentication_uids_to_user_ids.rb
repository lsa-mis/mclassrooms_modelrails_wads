# frozen_string_literal: true

# #903: every provider "email" row carried a second copy of users.email_address
# in uid. The model now assigns the user's id when the column is blank, which
# covers new rows only — this rewrites the ones that already exist. Data only:
# no DDL, so db/schema.rb is untouched.
class RewriteEmailAuthenticationUidsToUserIds < ActiveRecord::Migration[8.1]
  # The migration's own world, not the app's (spec/code_smells/frozen_migrations_spec.rb):
  # a literal table name and a literal `encrypts` declaration matching what the
  # column held at this timestamp, so uid round-trips through the deterministic
  # cipher without this file tracking a model a fork may rename.
  class MigrationAuthentication < ActiveRecord::Base
    self.table_name = "authentications"
    encrypts :uid, deterministic: true
  end

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
    encrypts :email_address, deterministic: true, downcase: true
  end

  BATCH_SIZE = 500

  # user_id is unique among email rows ((user_id, provider) is a unique index),
  # so the new values cannot collide with each other; and (provider, uid) scopes
  # the other index to email rows, so they cannot collide with an OAuth uid.
  #
  # find_each bounds MEMORY, not the transaction: Rails wraps the whole
  # migration in one (no disable_ddl_transaction! here), so on SQLite the
  # rewrite holds the writer lock from first row to last.
  def up
    MigrationAuthentication.where(provider: "email").find_each(batch_size: BATCH_SIZE) do |auth|
      auth.update!(uid: auth.user_id.to_s)
    end
  end

  # Deliberately re-creates the mirror #903 removed: `down` is the way back to
  # the previous release, whose writers all assume an email row's uid IS the
  # address. Restoring anything else would leave that release unable to keep
  # the two columns in step.
  def down
    MigrationAuthentication.where(provider: "email").find_each(batch_size: BATCH_SIZE) do |auth|
      user = MigrationUser.find_by(id: auth.user_id)
      auth.update!(uid: user.email_address) if user
    end
  end
end

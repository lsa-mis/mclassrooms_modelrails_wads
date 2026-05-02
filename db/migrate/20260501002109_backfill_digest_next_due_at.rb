class BackfillDigestNextDueAt < ActiveRecord::Migration[8.1]
  # Disable the wrapping DDL transaction so batched updates commit incrementally
  # rather than holding one giant write lock for the full population.
  disable_ddl_transaction!

  def up
    UserPreferences.unscoped.in_batches(of: 500) do |batch|
      batch.each do |prefs|
        # Spread first-cycle digest sends randomly across 24 hours to avoid
        # a thundering herd against DigestMailerJob's 15-minute polling cadence.
        # update_columns: skip validations/callbacks and don't bump updated_at —
        # this is system-initialization data, not a user-driven change.
        prefs.update_columns(
          digest_next_due_at: Time.current + rand(24).hours + rand(60).minutes
        )
      end
    end
  end

  def down
    UserPreferences.unscoped.update_all(digest_next_due_at: nil)
  end
end

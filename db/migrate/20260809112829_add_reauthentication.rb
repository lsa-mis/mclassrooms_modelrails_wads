class AddReauthentication < ActiveRecord::Migration[8.1]
  def change
    # When the session last proved a factor. Gates sensitive account changes.
    add_column :sessions, :reauthenticated_at, :datetime

    # Short-lived, single-use, user-bound email codes for re-authentication.
    # Deliberately NOT the magic-link token: no code path here mints a session,
    # and the per-user partial unique index keeps a sudo code from colliding
    # with an in-flight sign-in link.
    create_table :reauthentication_challenges do |t|
      t.references :user, null: false, foreign_key: true
      t.string :code_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :reauthentication_challenges, :user_id, unique: true,
              where: "consumed_at IS NULL", name: "index_active_reauth_challenge_per_user"
  end
end

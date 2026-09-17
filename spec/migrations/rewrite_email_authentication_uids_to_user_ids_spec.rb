# frozen_string_literal: true

require "rails_helper"
require_relative "../../db/migrate/20260907120000_rewrite_email_authentication_uids_to_user_ids"

# A data-only migration: no DDL, so there is no pre-migration state to reverse
# before the example. It builds the pre-#903 row by hand (uid mirroring the
# address, as every writer wrote it before this release), drives up and down,
# and RSpec's rollback undoes the writes.
RSpec.describe RewriteEmailAuthenticationUidsToUserIds do
  let(:migration) { described_class.new }
  let(:user) { create(:user) }

  it "replaces the mirrored address with the user's id, and restores it on down" do
    email_auth = user.authentications.email.sole
    email_auth.update_column(:uid, user.email_address)
    oauth = create(:authentication, :google, user: user)
    oauth_uid = oauth.uid

    ActiveRecord::Migration.suppress_messages { migration.up }

    expect(email_auth.reload.uid).to eq(user.id.to_s)
    expect(oauth.reload.uid).to eq(oauth_uid)

    ActiveRecord::Migration.suppress_messages { migration.down }

    expect(email_auth.reload.uid).to eq(user.email_address)
    expect(oauth.reload.uid).to eq(oauth_uid)
  end

  it "reads and writes uid through the same deterministic cipher the app uses" do
    email_auth = user.authentications.email.sole

    ActiveRecord::Migration.suppress_messages { migration.up }

    # Round-tripping through the app model is the proof: a migration that wrote
    # the id in the clear would raise here, not compare unequal.
    expect(Authentication.find(email_auth.id).uid).to eq(user.id.to_s)
  end
end

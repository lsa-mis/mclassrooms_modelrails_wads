# frozen_string_literal: true

module LegacyImport
  # The one user every imported note is credited to. The .invalid TLD
  # (RFC 2606) can never receive mail, and the account has no password and no
  # OAuth identity, so nobody can sign in as it.
  module Account
    EMAIL = "legacy-import@mclassrooms.invalid"

    def self.resolve(dry_run:)
      User.find_by(email_address: EMAIL) || (dry_run ? build : build.tap(&:save!))
    end

    def self.build = User.new(email_address: EMAIL, first_name: "Legacy", last_name: "import")
  end
end

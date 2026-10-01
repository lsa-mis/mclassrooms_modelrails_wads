# frozen_string_literal: true

module LegacyImport
  # The user every imported note is credited to; a .invalid address with no password or OAuth
  # identity, so nobody signs in as it. Creating it runs normal onboarding (see PR #90).
  module Account
    EMAIL = "legacy-import@mclassrooms.invalid"

    def self.resolve(dry_run:)
      User.find_by(email_address: EMAIL) || (dry_run ? build : build.tap(&:save!))
    end

    def self.build = User.new(email_address: EMAIL, first_name: "Legacy", last_name: "import")
  end
end

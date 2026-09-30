# frozen_string_literal: true

module LegacyImport
  # The importer's one door into Curation::Apply: the block's writes and the
  # audit row share one transaction, and the record is saved once at the end.
  # Returns nil on success or the failure message — it never raises, because
  # one bad record must not stop the other thousand.
  module Curate
    def self.call(record:, actor:, action:, attributes: {}, &writes)
      result = Curation::Apply.call(record:, actor:, action:, attributes:) do |r|
        writes&.call(r)
        r.save!
      end
      result.success? ? nil : result.errors.join(", ")
    rescue StandardError => e
      "#{e.class}: #{e.message}"
    end
  end
end

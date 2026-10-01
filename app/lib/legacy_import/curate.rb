# frozen_string_literal: true

module LegacyImport
  # The importer's one door into Curation::Apply: writes and audit row share a transaction.
  # Returns nil or the failure message and never raises, so one bad record can't stop the run.
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

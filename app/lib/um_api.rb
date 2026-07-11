# frozen_string_literal: true

# Error hierarchy for the U-M Facilities gateway client (roadmap Lib section;
# planning/plans/phase-2-ingestion.md Task 3). `UmApi::Client` (Task 5) and
# `UmApi::TokenCache` (this task) raise these instead of letting
# Net::HTTP/JSON errors leak, so every sync service (Tasks 6+) can rescue one
# namespace and map it to a `Result.failure` without knowing HTTP internals.
# Each subclass names a distinct response condition a caller may want to
# handle differently (e.g. RateLimited backing off, NotFound skipping a
# record) — kept as plain marker subclasses of Error with no extra state
# beyond the message, matching the rest of the app's exception style.
module UmApi
  class Error < StandardError; end

  class Unauthorized < Error; end

  class RateLimited < Error; end

  class ServerError < Error; end

  class NotFound < Error; end
end

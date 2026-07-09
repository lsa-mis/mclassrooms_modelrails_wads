# Operator-facing structured log for the phase-2 sync pipeline (Task 12 of
# planning/plans/phase-2-ingestion.md; roadmap Lib section; Brief §6.1). A
# dedicated `Logger` on `log/sync.log` — separate from `Rails.logger` — so an
# operator debugging a bad nightly run can `tail log/sync.log` without
# wading through every other request/job line in `log/production.log`.
#
# `#guidance_for(error)` is the plain-language mapping Brief §6.1 asks for:
# `UmApi::RateLimited` -> "safe to ignore unless repeated", `Unauthorized` ->
# "check credentials", `ServerError` -> "transient, re-run", `NotFound` ->
# "verify department mapping". It accepts three shapes:
#   - a `UmApi::Error` subclass itself (`guidance_for(UmApi::NotFound)`)
#   - a live instance (`guidance_for(UmApi::NotFound.new("..."))`)
#   - a bare message STRING
# The string case exists because of a structural gap between BasePhase and
# this class: Sync::BasePhase#call (Task 6) rescues every raised error and
# collapses it to `Result.failure(e.message, ...)` before the pipeline ever
# sees it (see base_phase.rb) — the original exception object/class never
# reaches Sync::RunPipeline. Rather than silently give up on guidance for
# the overwhelmingly common real-world case (a Result-based phase failure),
# #classify parses the status code back out of the message.
# `UmApi::Client#raise_for_status` (app/lib/um_api/client.rb) always formats
# its message as "U-M gateway returned <code> for <uri>" and maps codes to
# classes 1:1 (401/403 -> Unauthorized, 404 -> NotFound, 429 -> RateLimited,
# else -> ServerError) — the SAME two facts anchor this parse, so it isn't a
# guess, just recovering information BasePhase already had and dropped.
# A message that doesn't match (a non-UmApi StandardError, or wording that
# drifts from client.rb's format) falls through to DEFAULT_GUIDANCE rather
# than a wrong guess.
module Sync
  class OperatorLog
    LOG_PATH = Rails.root.join("log", "sync.log")

    GUIDANCE = {
      UmApi::RateLimited => "safe to ignore unless repeated",
      UmApi::Unauthorized => "check credentials",
      UmApi::ServerError => "transient, re-run",
      UmApi::NotFound => "verify department mapping"
    }.freeze

    DEFAULT_GUIDANCE = "no guidance on file for this error — investigate manually"

    STATUS_CODE_PATTERN = /gateway returned (\d+)/

    STATUS_CODE_CLASSES = {
      401 => UmApi::Unauthorized,
      403 => UmApi::Unauthorized,
      404 => UmApi::NotFound,
      429 => UmApi::RateLimited
    }.freeze

    def initialize(logger: Logger.new(LOG_PATH))
      @logger = logger
    end

    def guidance_for(error)
      GUIDANCE.fetch(classify(error), DEFAULT_GUIDANCE)
    end

    def phase_started(key)
      @logger.info("phase=#{key} status=started")
    end

    def phase_finished(key, result)
      if result.success?
        @logger.info("phase=#{key} status=succeeded counters=#{result.payload[:counters]}")
      else
        result.errors.each do |message|
          @logger.error("phase=#{key} status=failed error=#{message.inspect} guidance=#{guidance_for(message)}")
        end
      end
    end

    def phase_skipped(key)
      @logger.warn("phase=#{key} status=skipped")
    end

    # Used only when a phase class itself raises past the pipeline's own
    # defensive rescue (Sync::RunPipeline#run_phase) rather than returning a
    # Result the normal BasePhase way — the pipeline has the live exception
    # here, so guidance_for classifies it exactly, no string-parsing needed.
    def phase_errored(key, error)
      @logger.error(
        "phase=#{key} status=errored error_class=#{error.class} message=#{error.message.inspect} " \
        "guidance=#{guidance_for(error)}"
      )
    end

    def error(message)
      @logger.error(message)
    end

    private

    def classify(error)
      return error if error.is_a?(Class)
      return error.class if error.is_a?(Exception)

      match = STATUS_CODE_PATTERN.match(error.to_s)
      return nil unless match

      code = match[1].to_i
      return UmApi::ServerError if (500..599).cover?(code)

      STATUS_CODE_CLASSES[code]
    end
  end
end

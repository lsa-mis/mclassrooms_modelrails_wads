# Operator-facing structured log for the phase-2 sync pipeline (Task 12 of
# planning/plans/phase-2-ingestion.md; roadmap Lib section; Brief §6.1). A
# dedicated `Logger` on `log/sync.log` — separate from `Rails.logger` — so an
# operator debugging a bad nightly run can `tail log/sync.log` without
# wading through every other request/job line in `log/production.log`.
#
# `#guidance_for(error)` is the plain-language mapping Brief §6.1 asks for:
# `UmApi::RateLimited` -> "safe to ignore unless repeated", `Unauthorized` ->
# "check credentials", `ServerError` -> "transient, re-run", `NotFound` ->
# "verify department mapping". It maps by ERROR CLASS first, accepting:
#   - a failure `Result` (reads `payload[:error_class]`, the class name
#     Sync::BasePhase now stamps into every failure — base_phase.rb)
#   - the class-name STRING itself (`guidance_for("UmApi::Unauthorized")`)
#   - a `UmApi::Error` subclass (`guidance_for(UmApi::NotFound)`)
#   - a live instance (`guidance_for(UmApi::NotFound.new("..."))`)
#
# Why class-first, not message-first: Sync::BasePhase#call (Task 6) rescues
# every raised error and collapses it to `Result.failure(e.message,
# error_class: e.class.name, ...)`. The message wording varies per gateway
# path — UmApi::Client says "U-M gateway returned 401 for <uri>" but
# UmApi::TokenCache says "token endpoint returned 401 for scope <scope>",
# and every phase calls `token_for` (a possible 401) BEFORE any HTTP request
# — so a message regex anchored to the client's wording silently misses a
# token-endpoint 401, degrading exactly the "check credentials" case to
# generic guidance. The class carried in the Result is the reliable key.
#
# Message-regex FALLBACK only: for a genuinely foreign error (or a Result
# whose error_class isn't one of the four typed gateway errors), the status
# code is parsed back out of the message as a last resort —
# UmApi::Client#raise_for_status formats "...returned <code>..." and maps
# codes 1:1 (401/403 -> Unauthorized, 404 -> NotFound, 429 -> RateLimited,
# else -> ServerError). Anything that matches neither the class nor a code
# falls through to DEFAULT_GUIDANCE rather than a wrong guess.
module Sync
  class OperatorLog
    LOG_PATH = Rails.root.join("log", "sync.log")

    # Keyed by class NAME (string), so a failure Result carrying
    # `error_class: "UmApi::Unauthorized"` maps without needing the constant
    # resolved, and a class/instance maps via its `.name`.
    GUIDANCE = {
      "UmApi::RateLimited" => "safe to ignore unless repeated",
      "UmApi::Unauthorized" => "check credentials",
      "UmApi::ServerError" => "transient, re-run",
      "UmApi::NotFound" => "verify department mapping"
    }.freeze

    DEFAULT_GUIDANCE = "no guidance on file for this error — investigate manually"

    STATUS_CODE_PATTERN = /returned (\d+)/

    STATUS_CODE_CLASS_NAMES = {
      401 => "UmApi::Unauthorized",
      403 => "UmApi::Unauthorized",
      404 => "UmApi::NotFound",
      429 => "UmApi::RateLimited"
    }.freeze

    def initialize(logger: Logger.new(LOG_PATH))
      @logger = logger
    end

    def guidance_for(error)
      name = class_name_for(error)
      return GUIDANCE[name] if name && GUIDANCE.key?(name)

      fallback = class_name_from_message(message_for(error))
      return GUIDANCE[fallback] if fallback

      DEFAULT_GUIDANCE
    end

    def phase_started(key)
      @logger.info("phase=#{key} status=started")
    end

    def phase_finished(key, result)
      if result.success?
        @logger.info("phase=#{key} status=succeeded counters=#{result.payload[:counters]}")
      else
        # One guidance per failure Result — computed from the Result itself so
        # the error_class BasePhase stamped drives the mapping, not the (per-
        # gateway-path variable) message text.
        guidance = guidance_for(result)
        result.errors.each do |message|
          @logger.error("phase=#{key} status=failed error=#{message.inspect} guidance=#{guidance}")
        end
      end
    end

    def phase_skipped(key)
      @logger.warn("phase=#{key} status=skipped")
    end

    # Used only when a phase class itself raises past the pipeline's own
    # defensive rescue (Sync::RunPipeline#run_phase) rather than returning a
    # Result the normal BasePhase way — the pipeline has the live exception
    # here, so guidance_for classifies it by class exactly.
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

    # Resolves the error's CLASS NAME from whatever shape it arrives in. A
    # bare message String returns itself (harmless: it just won't match a
    # GUIDANCE key, and guidance_for falls through to the message regex).
    def class_name_for(error)
      case error
      when Result then error.payload[:error_class]
      when Class then error.name
      when Exception then error.class.name
      when String then error
      end
    end

    # The human-readable message to regex a status code out of, when no class
    # matched. For a Result that means its first error string; for an
    # exception, its message; for a String, itself.
    def message_for(error)
      case error
      when Result then error.errors.first
      when Exception then error.message
      when String then error
      end
    end

    def class_name_from_message(message)
      return nil unless message

      match = STATUS_CODE_PATTERN.match(message.to_s)
      return nil unless match

      code = match[1].to_i
      return "UmApi::ServerError" if (500..599).cover?(code)

      STATUS_CODE_CLASS_NAMES[code]
    end
  end
end

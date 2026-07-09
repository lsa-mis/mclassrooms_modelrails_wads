require "rails_helper"

# Task 12 of planning/plans/phase-2-ingestion.md: Sync::OperatorLog is a
# dedicated Logger for log/sync.log (never Rails.logger) plus the Brief §6.1
# error-class -> plain-language guidance mapping Sync::RunPipeline logs
# alongside every phase failure. Every example here injects `logger:` with a
# StringIO-backed Logger so nothing touches the real log/sync.log file.
RSpec.describe Sync::OperatorLog do
  let(:io) { StringIO.new }
  let(:log) { described_class.new(logger: Logger.new(io)) }

  def logged
    io.string
  end

  describe "#guidance_for" do
    it "maps UmApi::RateLimited to the rate-limit guidance" do
      expect(log.guidance_for(UmApi::RateLimited.new("429"))).to eq("safe to ignore unless repeated")
    end

    it "maps UmApi::Unauthorized to the credentials guidance" do
      expect(log.guidance_for(UmApi::Unauthorized.new("401"))).to eq("check credentials")
    end

    it "maps UmApi::ServerError to the transient guidance" do
      expect(log.guidance_for(UmApi::ServerError.new("500"))).to eq("transient, re-run")
    end

    it "maps UmApi::NotFound to the department-mapping guidance" do
      expect(log.guidance_for(UmApi::NotFound.new("404"))).to eq("verify department mapping")
    end

    it "accepts the error CLASS itself, not just an instance" do
      expect(log.guidance_for(UmApi::RateLimited)).to eq("safe to ignore unless repeated")
    end

    it "falls back to a default for an error class it doesn't recognize" do
      expect(log.guidance_for(StandardError.new("weird"))).to eq(Sync::OperatorLog::DEFAULT_GUIDANCE)
    end

    # BasePhase collapses every raised error to a bare message STRING before
    # Result ever reaches the pipeline (base_phase.rb) — guidance_for must
    # still classify the common real-world case by parsing the status code
    # UmApi::Client#raise_for_status (app/lib/um_api/client.rb) always
    # embeds: "U-M gateway returned <code> for <uri>".
    describe "given a bare message string (the shape a Sync::BasePhase Result actually carries)" do
      it "classifies a 429 message as rate-limited guidance" do
        expect(log.guidance_for("U-M gateway returned 429 for /bf/x")).to eq("safe to ignore unless repeated")
      end

      it "classifies a 401 message as credentials guidance" do
        expect(log.guidance_for("U-M gateway returned 401 for /bf/x")).to eq("check credentials")
      end

      it "classifies a 403 message as credentials guidance" do
        expect(log.guidance_for("U-M gateway returned 403 for /bf/x")).to eq("check credentials")
      end

      it "classifies a 404 message as department-mapping guidance" do
        expect(log.guidance_for("U-M gateway returned 404 for /bf/x")).to eq("verify department mapping")
      end

      it "classifies a 5xx message as transient guidance" do
        expect(log.guidance_for("U-M gateway returned 503 for /bf/x")).to eq("transient, re-run")
      end

      it "falls back to the default for a message that doesn't match the gateway format" do
        expect(log.guidance_for("unexpected boom")).to eq(Sync::OperatorLog::DEFAULT_GUIDANCE)
      end
    end

    # Task 12 fix: map by the CLASS carried in the failure Result, not by
    # re-parsing the message. Sync::BasePhase now stamps error_class into
    # every failure Result (base_phase.rb) precisely because message wording
    # varies per gateway path.
    describe "given a failure Result carrying error_class (the shape Sync::BasePhase now produces)" do
      it "maps by the carried error_class regardless of message text" do
        result = Result.failure("anything at all, no status code in here", error_class: "UmApi::Unauthorized")
        expect(log.guidance_for(result)).to eq("check credentials")
      end

      # The live defect this fix targets: UmApi::TokenCache raises
      # Unauthorized as "token endpoint returned {code} for scope ..." — a
      # DIFFERENT message shape than UmApi::Client's "gateway returned ...",
      # and every phase calls token_for BEFORE any HTTP request, so a
      # token-endpoint 401 is reachable on a real nightly run. The message
      # here even carries a MISLEADING 500 that message-parsing would mis-map
      # to "transient, re-run"; class-first mapping still yields the correct
      # "check credentials". Under pure string-parsing this returns the wrong
      # guidance (or generic), so this example has teeth.
      it "maps a TokenCache-shaped Unauthorized to credentials guidance, not a message-parsed guess" do
        result = Result.failure("token endpoint returned 500 for scope buildings", error_class: "UmApi::Unauthorized")
        expect(log.guidance_for(result)).to eq("check credentials")
      end

      it "still falls back to message parsing when the Result's error_class is a foreign (non-UmApi) class" do
        result = Result.failure("U-M gateway returned 404 for /bf/x", error_class: "SomeGem::Timeout")
        expect(log.guidance_for(result)).to eq("verify department mapping")
      end
    end

    describe "given the error_class name string directly" do
      it "maps UmApi::Unauthorized to credentials guidance" do
        expect(log.guidance_for("UmApi::Unauthorized")).to eq("check credentials")
      end
    end
  end

  describe "#phase_started" do
    it "logs the phase key at info level" do
      log.phase_started("campuses")
      expect(logged).to include("phase=campuses").and include("started")
    end
  end

  describe "#phase_finished" do
    it "logs counters on success" do
      log.phase_finished("campuses", Result.success(counters: { "created" => 3 }, warnings: []))
      expect(logged).to include("phase=campuses").and include("succeeded").and include("created")
    end

    it "logs every error message with its guidance on failure" do
      log.phase_finished("buildings", Result.failure("U-M gateway returned 401 for /bf/x"))
      expect(logged).to include("phase=buildings").and include("failed").and include("check credentials")
    end

    it "derives guidance from the failure Result's error_class, not its (per-gateway-path variable) message" do
      # The exact pipeline call path: a token-endpoint 401 Result whose
      # message would mis-parse (500) but whose error_class is authoritative.
      result = Result.failure("token endpoint returned 500 for scope buildings", error_class: "UmApi::Unauthorized")
      log.phase_finished("campuses", result)
      expect(logged).to include("check credentials")
      expect(logged).not_to include("transient, re-run")
    end
  end

  describe "#phase_skipped" do
    it "logs the phase key at warn level" do
      log.phase_skipped("rooms")
      expect(logged).to include("phase=rooms").and include("skipped")
    end
  end

  describe "#phase_errored" do
    it "logs the error class, message, and exact guidance" do
      log.phase_errored("facility_ids", UmApi::NotFound.new("gone"))
      expect(logged).to include("facility_ids").and include("UmApi::NotFound").and include("verify department mapping")
    end
  end

  describe "#error" do
    it "logs a bare message at error level" do
      log.error("pipeline blew up")
      expect(logged).to include("pipeline blew up")
    end
  end
end

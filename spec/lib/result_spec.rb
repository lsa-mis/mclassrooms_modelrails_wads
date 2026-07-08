require "rails_helper"

# Fork-wide convention (roadmap Lib section, spec D7): every sync phase (and
# later phases 6/8) returns a Result. This spec locks the contract exactly:
# `Result.success(**payload)` / `Result.failure(*errors, **payload)`,
# `#success?`, `#errors` (array of strings), `#payload` (hash) — plus
# immutability, since Result is a Data.define value object with no setters.
RSpec.describe Result do
  describe ".success" do
    it "is success? with no errors" do
      result = Result.success

      expect(result.success?).to be(true)
      expect(result.errors).to eq([])
    end

    it "carries the payload hash" do
      result = Result.success(counters: { created: 1 }, warnings: [])

      expect(result.payload[:counters]).to eq({ created: 1 })
      expect(result.payload[:warnings]).to eq([])
    end
  end

  describe ".failure" do
    it "is not success? and carries the given errors" do
      result = Result.failure("boom")

      expect(result.success?).to be(false)
      expect(result.errors).to eq([ "boom" ])
    end

    it "carries the payload hash alongside the errors" do
      result = Result.failure("boom", counters: { created: 0 })

      expect(result.payload[:counters]).to eq({ created: 0 })
    end

    it "coerces multiple varargs errors into an array of strings" do
      result = Result.failure("a", "b")

      expect(result.errors).to eq([ "a", "b" ])
    end

    it "flattens an array of errors passed as a single arg" do
      result = Result.failure([ "a", "b" ])

      expect(result.errors).to eq([ "a", "b" ])
    end

    it "coerces a symbol error into a string" do
      result = Result.failure(:sym)

      expect(result.errors).to eq([ "sym" ])
    end

    it "drops nil errors rather than coercing them to blank strings" do
      result = Result.failure(nil)

      expect(result.errors).to eq([])
    end

    it "drops nils interleaved among real errors" do
      result = Result.failure("a", nil, "b")

      expect(result.errors).to eq([ "a", "b" ])
    end

    it "yields an empty error list when called with no args" do
      result = Result.failure

      expect(result.success?).to be(false)
      expect(result.errors).to eq([])
    end

    it "defaults payload to an empty hash when none is given" do
      result = Result.failure("boom")

      expect(result.payload).to eq({})
    end
  end

  describe "immutability" do
    it "is frozen" do
      expect(Result.success).to be_frozen
    end

    it "exposes no writer methods" do
      result = Result.success

      expect(result).not_to respond_to(:success=)
      expect(result).not_to respond_to(:errors=)
      expect(result).not_to respond_to(:payload=)
    end

    # The Data instance being frozen doesn't freeze the hash/array it holds:
    # without an explicit freeze at construction, `result.payload[:k] = v` and
    # `result.errors << x` mutate the shared object in place. Result is the
    # fork-wide contract every sync phase passes around, so pin the shallow
    # freeze on both members.
    it "freezes the payload hash" do
      result = Result.success(counters: { created: 1 })

      expect(result.payload).to be_frozen
    end

    it "freezes the errors array" do
      result = Result.failure("boom")

      expect(result.errors).to be_frozen
    end

    it "raises rather than allowing the errors array to be appended to" do
      result = Result.failure("boom")

      expect { result.errors << "sneaky" }.to raise_error(FrozenError)
    end

    it "raises rather than allowing the payload hash to be written to" do
      result = Result.success(counters: { created: 1 })

      expect { result.payload[:injected] = 999 }.to raise_error(FrozenError)
    end
  end
end

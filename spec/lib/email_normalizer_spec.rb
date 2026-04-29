require "rails_helper"

RSpec.describe EmailNormalizer do
  describe ".normalize" do
    it "lowercases ASCII addresses" do
      expect(described_class.normalize("Alice@Example.COM")).to eq("alice@example.com")
    end

    it "strips surrounding whitespace" do
      expect(described_class.normalize("  alice@example.com  ")).to eq("alice@example.com")
    end

    it "returns nil for nil input" do
      expect(described_class.normalize(nil)).to be_nil
    end

    it "returns nil for empty string" do
      expect(described_class.normalize("")).to be_nil
    end

    it "returns nil for whitespace-only input" do
      expect(described_class.normalize("   ")).to be_nil
    end

    it "normalizes NFD-encoded characters to NFC form (combining-mark composition)" do
      # "café" can be NFC ("é" as single codepoint U+00E9) or NFD ("e" + combining
      # acute U+0301). Visually identical, byte-different. Canonical form is NFC.
      nfd_email = "caf" + "é" + "@example.com"  # NFD: e + combining acute
      nfc_email = "café@example.com"                    # NFC: é as one codepoint

      expect(nfd_email.bytesize).not_to eq(nfc_email.bytesize)  # sanity: actually different bytes

      expect(described_class.normalize(nfd_email)).to eq(described_class.normalize(nfc_email))
      expect(described_class.normalize(nfd_email).unicode_normalized?(:nfc)).to be true
    end

    it "preserves non-ASCII characters in the normalized output" do
      expect(described_class.normalize("üser@example.com")).to eq("üser@example.com")
    end

    it "handles internal whitespace by NOT collapsing it (only strips ends)" do
      # Internal whitespace would make this an invalid email, but normalization
      # should not silently mangle it — leave invalidity for the validator.
      expect(described_class.normalize(" not an  email ")).to eq("not an  email")
    end

    it "is idempotent (normalizing twice gives same result)" do
      input = "  Café@Example.COM  "
      once = described_class.normalize(input)
      twice = described_class.normalize(once)
      expect(twice).to eq(once)
    end
  end

  describe ".equivalent?" do
    it "returns true for two identical normalized addresses" do
      expect(described_class.equivalent?("alice@example.com", "alice@example.com")).to be true
    end

    it "returns true across case differences" do
      expect(described_class.equivalent?("ALICE@example.com", "alice@EXAMPLE.com")).to be true
    end

    it "returns true across NFC vs NFD encoding (the load-bearing case)" do
      nfd = "caf" + "é" + "@example.com"
      nfc = "café@example.com"
      expect(described_class.equivalent?(nfd, nfc)).to be true
    end

    it "returns true across whitespace differences" do
      expect(described_class.equivalent?("  alice@example.com", "alice@example.com  ")).to be true
    end

    it "returns false for different addresses" do
      expect(described_class.equivalent?("alice@example.com", "bob@example.com")).to be false
    end

    it "returns false when either side is nil" do
      expect(described_class.equivalent?(nil, "alice@example.com")).to be false
      expect(described_class.equivalent?("alice@example.com", nil)).to be false
      expect(described_class.equivalent?(nil, nil)).to be false
    end

    it "returns false when either side is empty/whitespace-only" do
      expect(described_class.equivalent?("", "alice@example.com")).to be false
      expect(described_class.equivalent?("   ", "alice@example.com")).to be false
    end
  end

  describe "documented limitation: IDN punycode is NOT handled" do
    # The Unicode form and the punycode form of an IDN domain are different.
    # Adding addressable gem (or similar) would close this; deferred unless
    # a real interop concern surfaces.
    it "does NOT consider Unicode and punycode forms of the same domain equivalent" do
      unicode_form = "user@bücher.de"
      punycode_form = "user@xn--bcher-kva.de"

      expect(described_class.equivalent?(unicode_form, punycode_form)).to be false
    end
  end
end

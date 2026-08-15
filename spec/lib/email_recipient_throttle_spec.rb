require "rails_helper"

RSpec.describe EmailRecipientThrottle do
  # Test env defaults to :null_store, which makes Rails.cache.increment return nil
  # and the throttle's fail-open path always returns true. Swap to :memory_store
  # for these specs so we can actually exercise the cap.
  around do |ex|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ex.run
  ensure
    Rails.cache = original
  end

  describe ".allow!" do
    it "allows the first CAP sends, then blocks" do
      email = "alice@example.com"
      results = (described_class::CAP + 1).times.map { described_class.allow!(email, kind: :verification) }

      expect(results.first(described_class::CAP)).to all(be true)
      expect(results.last).to be false
    end

    it "applies the per-kind policy for :magic_link (5 sends per 15 minutes)" do
      email = "alice@example.com"
      policy = described_class::KIND_POLICIES.fetch(:magic_link)
      expect(policy).to eq(cap: 5, window: 15.minutes)

      results = (policy[:cap] + 1).times.map { described_class.allow!(email, kind: :magic_link) }
      expect(results.first(policy[:cap])).to all(be true)
      expect(results.last).to be false
    end

    it "tracks separate buckets per kind for the same recipient" do
      email = "alice@example.com"
      described_class::CAP.times { described_class.allow!(email, kind: :verification) }

      # Verification bucket is exhausted; collision_alert should still allow.
      expect(described_class.allow!(email, kind: :verification)).to be false
      expect(described_class.allow!(email, kind: :collision_alert)).to be true
    end

    it "treats addresses that normalize to the same canonical form as the same recipient" do
      # NFD vs NFC encoding of the same visual address must share a bucket;
      # otherwise an attacker could bypass the cap by sending alternating forms.
      nfc = "café@example.com"
      nfd = "caf" + "é" + "@example.com"

      described_class::CAP.times { described_class.allow!(nfc, kind: :verification) }
      expect(described_class.allow!(nfd, kind: :verification)).to be false
    end

    it "treats case differences as the same recipient" do
      described_class::CAP.times { described_class.allow!("Alice@Example.com", kind: :verification) }
      expect(described_class.allow!("alice@example.com", kind: :verification)).to be false
    end

    it "allows again after the window expires" do
      email = "alice@example.com"
      described_class::CAP.times { described_class.allow!(email, kind: :verification) }
      expect(described_class.allow!(email, kind: :verification)).to be false

      travel described_class::WINDOW + 1.minute do
        expect(described_class.allow!(email, kind: :verification)).to be true
      end
    end

    it "fails open if the cache backend cannot increment (returns nil)" do
      # null_store returns nil from increment; under that condition we want sends
      # to go through (degraded throttle is better than dropped mail).
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::NullStore.new

      expect(described_class.allow!("alice@example.com", kind: :verification)).to be true
    ensure
      Rails.cache = original
    end
  end

  describe ".reset!" do
    it "clears the recipient's counter for a kind" do
      email = "alice@example.com"
      described_class::CAP.times { described_class.allow!(email, kind: :verification) }
      expect(described_class.allow!(email, kind: :verification)).to be false

      described_class.reset!(email, kind: :verification)
      expect(described_class.allow!(email, kind: :verification)).to be true
    end
  end

  describe ".cache_key" do
    it "is deterministic for canonically-equivalent inputs" do
      a = described_class.cache_key("Alice@Example.com", :verification)
      b = described_class.cache_key("  alice@example.com  ", :verification)
      expect(a).to eq(b)
    end

    it "differs across kinds" do
      verification = described_class.cache_key("alice@example.com", :verification)
      collision = described_class.cache_key("alice@example.com", :collision_alert)
      expect(verification).not_to eq(collision)
    end

    it "does not include the raw email address (privacy)" do
      key = described_class.cache_key("alice@example.com", :verification)
      expect(key).not_to include("alice@example.com")
      expect(key).to start_with("email_recipient_throttle:verification:")
    end
  end
end

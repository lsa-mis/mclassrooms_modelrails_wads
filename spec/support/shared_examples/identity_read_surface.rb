# Contract: define let(:identity)            — wraps a model with NO image
#           let(:identity_with_image)        — wraps a model with image + original attached
#           let(:expected_initials)          — literal expected initials string
RSpec.shared_examples "an identity read surface" do
  describe "#image? / #image" do
    it "is false with no attachment" do
      expect(identity.image?).to be(false)
    end

    it "is true with an attachment, and #image returns the attachment proxy" do
      expect(identity_with_image.image?).to be(true)
      expect(identity_with_image.image).to be_attached
    end
  end

  describe "#croppable_image" do
    it "prefers the original when attached (re-crops must not degrade quality)" do
      expect(identity_with_image.croppable_image).to eq(identity_with_image.image_original)
    end

    it "falls back to the cropped image when no original exists" do
      identity_with_image.image_original.purge
      expect(identity_with_image.croppable_image).to eq(identity_with_image.image)
    end
  end

  describe "#image_updated_at" do
    it "is nil with no attachment" do
      expect(identity.image_updated_at).to be_nil
    end

    it "returns the blob creation time when attached" do
      expect(identity_with_image.image_updated_at).to eq(identity_with_image.image.blob.created_at)
    end
  end

  describe "#initials" do
    it "returns the model's initials" do
      expect(identity.initials).to eq(expected_initials)
    end
  end

  describe "#hue" do
    it "defaults to 210 when primary_color is nil" do
      expect(identity.hue).to eq(210)
    end
  end

  # #653: the case-on-source lives on Identity, not in view helpers. nil means
  # "render initials". Upload variants need a URL resolver with route context
  # (main_app.url_for), supplied by the caller as the block.
  describe "#image_url" do
    it "is nil when the identity renders initials (resolver never runs)" do
      expect(identity.image_url(size: 40) { raise "resolver must not run" }).to be_nil
    end

    it "yields the sized variant to the resolver for an uploaded image" do
      url = identity_with_image.image_url(size: 40) do |variant|
        "resolved:#{variant.variation.transformations[:resize_to_fill].join('x')}"
      end
      expect(url).to eq("resolved:40x40")
    end
  end

  describe "#uploaded_image?" do
    it "is true only for an upload source with an attached image" do
      expect(identity_with_image.uploaded_image?).to be(true)
      expect(identity.uploaded_image?).to be(false)
    end
  end

  # #755: one hue rule for every initials render — nil at the default so the
  # component's bg-interactive branch applies; the custom hue otherwise.
  describe "#custom_hue" do
    it "is nil at the default color" do
      expect(identity.custom_hue).to be_nil
    end
  end

  describe "#resolve_source" do
    it "returns the requested source when it is available" do
      available = identity.available_sources.first
      expect(identity.resolve_source(available)).to eq(available)
    end

    it "falls back to the current source for an unavailable request" do
      expect(identity.resolve_source("nonsense")).to eq(identity.source)
    end

    it "falls back to the current source for a blank request" do
      expect(identity.resolve_source(nil)).to eq(identity.source)
      expect(identity.resolve_source("")).to eq(identity.source)
    end
  end
end

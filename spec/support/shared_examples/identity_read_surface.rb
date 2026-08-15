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

require "rails_helper"

RSpec.describe CropHelper, type: :helper do
  let(:user) { create(:user) }

  before do
    user.avatar.attach(
      io: File.open(Rails.root.join("spec/fixtures/files/avatar.png")),
      filename: "avatar.png",
      content_type: "image/png"
    )
  end

  describe "#cropped_variant" do
    context "without crop metadata" do
      it "returns a variant with resize_to_fill only" do
        variant = helper.cropped_variant(user.avatar, resize_to: [ 128, 128 ])
        expect(variant).to be_a(ActiveStorage::VariantWithRecord)
        expect(variant.variation.transformations).to include(resize_to_fill: [ 128, 128 ])
        expect(variant.variation.transformations).not_to have_key(:crop)
      end
    end

    context "with crop metadata" do
      before do
        blob = user.avatar.blob
        blob.update_columns(
          metadata: blob.metadata.merge("crop" => { "x" => 10, "y" => 20, "w" => 100, "h" => 100 })
        )
        blob.reload
      end

      it "returns a variant with crop and resize_to_fill" do
        variant = helper.cropped_variant(user.avatar, resize_to: [ 128, 128 ])
        expect(variant).to be_a(ActiveStorage::VariantWithRecord)
        expect(variant.variation.transformations).to include(
          crop: [ 10, 20, 100, 100 ],
          resize_to_fill: [ 128, 128 ]
        )
      end
    end

    context "with partial crop metadata" do
      before do
        blob = user.avatar.blob
        blob.update_columns(
          metadata: blob.metadata.merge("crop" => { "x" => 0 })
        )
        blob.reload
      end

      it "falls back to resize-only when crop data is incomplete" do
        variant = helper.cropped_variant(user.avatar, resize_to: [ 128, 128 ])
        expect(variant.variation.transformations).not_to have_key(:crop)
      end
    end
  end
end

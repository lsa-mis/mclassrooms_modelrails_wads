module CropHelper
  def cropped_variant(attachment, resize_to:)
    crop = attachment.blob.metadata["crop"]

    if crop.present? && %w[x y w h].all? { |k| crop[k].present? } &&
        crop["w"].to_i > 0 && crop["h"].to_i > 0
      attachment.variant(
        crop: [ crop["x"].to_i, crop["y"].to_i, crop["w"].to_i, crop["h"].to_i ],
        resize_to_fill: resize_to
      )
    else
      attachment.variant(resize_to_fill: resize_to)
    end
  end
end

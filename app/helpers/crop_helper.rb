module CropHelper
  def cropped_variant(attachment, resize_to:)
    crop = attachment.blob.metadata["crop"]

    if crop.present? && %w[x y w h].all? { |k| crop[k].present? }
      attachment.variant(
        crop: "#{crop['w']}x#{crop['h']}+#{crop['x']}+#{crop['y']}",
        resize_to_fill: resize_to
      )
    else
      attachment.variant(resize_to_fill: resize_to)
    end
  end
end

module CropCoordinatable
  extend ActiveSupport::Concern

  private

  def safe_parse_coordinates(raw)
    return nil if raw.blank?

    parsed = JSON.parse(raw)
    return nil unless parsed.is_a?(Hash)
    return nil unless %w[x y w h].all? { |k| parsed[k].is_a?(Numeric) }

    parsed.slice("x", "y", "w", "h")
  rescue JSON::ParserError
    nil
  end
end

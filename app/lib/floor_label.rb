# frozen_string_literal: true

# The floor-label rule the sync and the legacy import share: "01" -> "1", "0G" -> "G", "00" -> "0".
module FloorLabel
  def self.normalize(raw) = raw.to_s.strip.sub(/\A0+(?=.)/, "")
end

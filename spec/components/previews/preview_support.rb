# frozen_string_literal: true

require "cgi"

# Shared helpers for Lookbook preview templates.
# Include in preview classes: include PreviewSupport
# Or call directly from ERBs: PreviewSupport.placeholder_image_uri(w, h)
module PreviewSupport
  # Returns a data:image/svg+xml URI for a placeholder rectangle.
  # width/height must match the slot dimensions so layout is correct.
  def self.placeholder_image_uri(width, height, label = "#{width}×#{height}")
    svg = %(<svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}"><rect width="100%" height="100%" fill="#94a3b8"/><text x="50%" y="50%" dominant-baseline="middle" text-anchor="middle" font-family="sans-serif" font-size="#{[ width / 10, 14 ].min}" fill="#fff">#{label}</text></svg>)
    "data:image/svg+xml,#{CGI.escape(svg)}"
  end

  # Instance-method form for use inside preview classes that include this module.
  def placeholder_image(width, height, label = "#{width}×#{height}")
    PreviewSupport.placeholder_image_uri(width, height, label)
  end
end

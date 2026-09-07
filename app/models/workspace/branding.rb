class Workspace < ApplicationRecord
  # A workspace's visual identity: its logo (an upload or its initials) and hue.
  module Branding
    extend ActiveSupport::Concern

    included do
      has_one_attached :logo
      has_one_attached :logo_original

      # ApplicationRecord's constant: lexical lookup from inside this module sees Workspace's own
      # constants but not Workspace's ancestors'.
      validates :logo,
        content_type: ApplicationRecord::IMAGE_CONTENT_TYPES,
        size: { less_than: 5.megabytes }
      validates :logo_original,
        content_type: ApplicationRecord::IMAGE_CONTENT_TYPES,
        size: { less_than: 10.megabytes }
      validates :primary_color, inclusion: { in: 0..360 }, allow_nil: true
      validates :logo_source, inclusion: { in: %w[upload initials] }
    end

    def initials
      name.split.map(&:first).take(2).join.upcase
    end

    def available_logo_sources
      %w[upload initials]
    end
  end
end

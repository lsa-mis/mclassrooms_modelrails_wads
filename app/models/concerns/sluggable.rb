# Generates a URL-safe slug from the model's name. Handles collisions by
# appending a counter. Override slug_taken? in models that scope uniqueness
# (e.g., Project scopes to workspace, Workspace checks globally).
module Sluggable
  extend ActiveSupport::Concern

  included do
    before_validation :generate_slug, if: -> { name.present? && (slug.blank? || (name_changed? && !slug_changed?)) }
  end

  private

  def generate_slug
    prefix = self.class.name.underscore.parameterize
    base_slug = name.parameterize
    base_slug = "#{prefix}-#{SecureRandom.hex(4)}" if base_slug.blank?
    self.slug = base_slug
    counter = 1
    while slug_taken?(slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  end

  # Default: globally unique within the model's table.
  # Override for scoped uniqueness (e.g., unique within a workspace).
  def slug_taken?(candidate)
    self.class.where.not(id: id).exists?(slug: candidate)
  end
end

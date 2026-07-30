# Layer 1 (generic, no domain coupling). Declares metadata-bearing Active
# Storage "slots" and resolves stored-wins-else-derived alt text. See
# planning/specs/2026-07-23-mclassrooms-image-metadata-alt-fallback-design.md.
module Describable
  extend ActiveSupport::Concern

  # class-name => model, so the coverage report + ratchet enumerate consumers
  # without a hardcoded list. Keyed by name to survive dev-mode reloads.
  mattr_accessor :registry, default: {}

  class_methods do
    # describable :panorama, derived_alt: ->(rec) { I18n.t("media.derived_alt.panorama", room: rec.display_name) }
    # Expects columns #{slot}_alt, #{slot}_description, #{slot}_derived_ok.
    def describable(slot, derived_alt:)
      describable_slots[slot.to_sym] = derived_alt
      Describable.registry[name] = self
    end

    def describable_slots
      @describable_slots ||= {}
    end
  end

  def alt_for(slot)
    slot = slot.to_sym
    read_attribute("#{slot}_alt").presence || self.class.describable_slots.fetch(slot).call(self)
  end

  def description_for(slot)
    read_attribute("#{slot}_description").presence
  end

  def alt_status_for(slot)
    slot = slot.to_sym
    return :authored if read_attribute("#{slot}_alt").present?
    return :derived_ok if read_attribute("#{slot}_derived_ok")

    :needs_review
  end

  def needs_alt_review?(slot)
    alt_status_for(slot) == :needs_review
  end
end

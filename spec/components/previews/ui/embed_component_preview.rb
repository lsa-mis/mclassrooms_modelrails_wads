# frozen_string_literal: true

module UI
  # # Embed
  #
  # Embeds third-party content from a `url:` (provider auto-detected from the domain)
  # or, for Google Maps, a `query:`. Renders a titled, lazy-loaded `<iframe>` inside a
  # responsive aspect-ratio wrapper.
  #
  # ## Accessibility contract
  # - **Guarantees:** every iframe carries a non-blank `title` (i18n, per-provider
  #   default) so screen readers announce the embedded region.
  # - **You supply:** a recognised provider `url:` (or a maps `query:`).
  # @logical_path Media
  class EmbedComponentPreview < ViewComponent::Preview
    include UIHelper

    # A YouTube video embed (titled iframe, 16/9 aspect).
    def youtube
    end

    # A Google Maps embed from a search query (titled iframe, 16/9 aspect).
    def map
    end
  end
end

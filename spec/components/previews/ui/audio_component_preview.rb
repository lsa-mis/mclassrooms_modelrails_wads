# frozen_string_literal: true

module UI
  # # Audio
  #
  # A native `<audio>` player. Add one or more `<source>` elements via
  # `a.with_source(src:, type:)`; the browser picks the first it can play.
  #
  # ## Accessibility contract
  # - **Guarantees:** native browser controls (keyboard-operable, labelled by the UA).
  # - **You supply:** at least one playable `source`.
  # @logical_path Media
  class AudioComponentPreview < ViewComponent::Preview
    include UIHelper

    # Native controls with a single MP3 source.
    def default
    end

    # Multiple sources (ogg then mp3) with looping enabled.
    def multi_source
    end
  end
end

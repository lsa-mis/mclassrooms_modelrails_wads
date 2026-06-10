# frozen_string_literal: true

module UI
  # # Video
  #
  # A native `<video>` player. Add `<source>` elements via `v.with_source(src:, type:)`
  # and caption/subtitle `<track>` elements via `v.with_track(src:, kind:, label:, srclang:)`.
  #
  # ## Accessibility contract
  # - **Guarantees:** native browser controls (keyboard-operable, UA-labelled);
  #   a `<track kind="captions">` is exposed to the UA's captions menu.
  # - **You supply:** at least one playable `source` and — for AAA media — captions.
  # @logical_path Media
  class VideoComponentPreview < ViewComponent::Preview
    include UIHelper

    # Native controls with a poster image and a single MP4 source.
    def default
    end

    # An MP4 source with an English captions track (kind: :captions, default).
    def captions
    end
  end
end

# frozen_string_literal: true

module UI
  class AudioComponent < ApplicationComponent
    # HTML5 <audio> element with multiple source formats and playback controls.
    # Usage, options and the accessibility contract: docs/components/audio.md in the
    # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
    renders_many :sources, "UI::AudioComponent::SourceComponent"

    PRELOADS = %i[auto metadata none].freeze

    # controls:    show native browser controls (default: true)
    # autoplay:    start playing automatically — requires muted: true in some browsers
    # muted:       mute the audio track
    # loop:        loop playback
    # preload:     :auto | :metadata (default) | :none
    def initialize(controls: true, autoplay: false, muted: false,
                   loop: false, preload: :metadata, **html_attrs)
      @controls = controls
      @autoplay = autoplay
      @muted    = muted
      @loop     = loop
      @preload  = coerce_preload(preload)
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      attrs = { preload: @preload, class: cn(@extra_class) }
      attrs[:controls] = true if @controls
      attrs[:autoplay] = true if @autoplay
      attrs[:muted]    = true if @muted
      attrs[:loop]     = true if @loop

      content_tag(:audio, **attrs, **@html_attrs) do
        sources.each { |s| concat s }
        concat content if content?
      end
    end

    private

    # Fail loud so a typo'd preload is caught immediately (not silently dropped to the attr).
    def coerce_preload(value)
      sym = value.to_sym
      return sym if PRELOADS.include?(sym)

      raise ArgumentError, "unknown preload #{value.inspect} — use one of #{PRELOADS.join(', ')}"
    end

    # Represents a <source> element inside <audio>.
    # a.with_source(src: "audio.mp3", type: "audio/mpeg")
    class SourceComponent < ApplicationComponent
      def initialize(src:, type:, **html_attrs)
        @src  = src
        @type = type
        @html_attrs = html_attrs
      end

      def call
        tag.source(src: @src, type: @type, **@html_attrs)
      end
    end
  end
end

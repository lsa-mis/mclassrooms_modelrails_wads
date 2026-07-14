# frozen_string_literal: true

module UI
  class CarouselComponent < ApplicationComponent
    # Slide carousel (APG "basic" pattern): prev/next + slide-picker dots, all real
    # <button>s with ≥44px targets. Autoplay (when > 0) is WCAG 2.2.2 compliant — a
    # pause/play toggle, pause on hover/focus, disabled under prefers-reduced-motion.
    #
    # Usage:
    #   ui :carousel, label: "Featured photos" do |c|
    #     c.with_slide { image_tag "slide1.jpg" }
    #     c.with_slide { image_tag "slide2.jpg" }
    #   end

    TRACK_CLS = "flex transition-transform duration-300 motion-reduce:transition-none"
    # w-full (definite, not min-w-full) so a percentage-width child resolves against
    # it instead of falling back to the image's intrinsic width and overflowing the
    # slide; overflow-hidden flips the flex min-width:auto to 0 so wide content can't
    # widen the slide past one frame (else translateX(-100%) lands slides partially).
    SLIDE_CLS = "w-full shrink-0 overflow-hidden"

    BTN_BASE  = "absolute top-1/2 z-10 -translate-y-1/2 inline-flex size-11 items-center justify-center " \
                "rounded-full bg-surface-raised/95 backdrop-blur border border-border shadow-sm " \
                "transition hover:bg-surface-raised disabled:opacity-40 focus-ring"
    BTN_PREV  = "left-2"
    BTN_NEXT  = "right-2"

    PAUSE_CLS = "absolute bottom-2 right-2 z-10 inline-flex size-11 items-center justify-center " \
                "rounded-full bg-surface-raised/80 backdrop-blur border border-border shadow-sm focus-ring"

    DOTS_CLS  = "mt-3 flex justify-center gap-0.5"
    # 44px hit area carries an 8px visual dot via ::before (target-size without a giant dot).
    DOT_CLS   = "grid size-11 place-items-center rounded-full focus-ring " \
                "before:size-2 before:rounded-full before:bg-text-muted/40 before:transition " \
                "aria-[current=true]:before:w-4 aria-[current=true]:before:bg-interactive"

    CHEVRON_L = "m15 18-6-6 6-6"
    CHEVRON_R = "m9 18 6-6-6-6"
    PLAY_PATH  = "m6 3 14 9-14 9z"
    PAUSE_PATH = "M6 4h4v16H6zM14 4h4v16h-4z"

    renders_many :slides

    # loop:        wrap at the ends (default true)
    # indicators:  show dots (default true)
    # autoplay:    interval ms, 0 = off (default 0)
    # label:       accessible name for the carousel region (i18n default "Carousel")
    def initialize(loop: true, indicators: true, autoplay: 0, label: nil, **html_attrs)
      @loop        = loop
      @indicators  = indicators
      @autoplay    = autoplay.to_i
      @label       = label
      @extra_class = html_attrs.delete(:class)
      @html_attrs  = html_attrs
    end

    def call
      content_tag(:div,
        class: cn("relative overflow-hidden", @extra_class),
        role: "group",
        "aria-roledescription": "carousel",
        "aria-label": @label || t("ui.carousel.label", default: "Carousel"),
        data: root_data,
        **@html_attrs) do
        concat track
        concat prev_btn
        concat next_btn
        concat pause_btn if @autoplay.positive?
        concat dots if @indicators && slides.size > 1
        concat live_region
      end
    end

    private

    def root_data
      data = {
        controller: "carousel",
        carousel_loop_value: @loop,
        carousel_autoplay_value: @autoplay
      }
      # Pause on hover/focus; resume on leave/blur (only if it was autoplaying).
      data[:action] = "mouseenter->carousel#suspend mouseleave->carousel#resume " \
                      "focusin->carousel#suspend focusout->carousel#resume" if @autoplay.positive?
      data
    end

    def track
      content_tag(:div, class: TRACK_CLS, data: { carousel_target: "track" }) do
        safe_join(slides.each_with_index.map { |s, i| slide(s, i) })
      end
    end

    def slide(content, index)
      content_tag(:div, content,
        class: SLIDE_CLS,
        role: "group",
        "aria-roledescription": "slide",
        "aria-label": t("ui.carousel.slide", n: index + 1, count: slides.size, default: "%{n} of %{count}"))
    end

    def prev_btn
      control_btn(BTN_PREV, t("ui.carousel.previous", default: "Previous slide"), "carousel#prev", CHEVRON_L)
    end

    def next_btn
      control_btn(BTN_NEXT, t("ui.carousel.next", default: "Next slide"), "carousel#next", CHEVRON_R)
    end

    def control_btn(pos, label, action, path)
      content_tag(:button, chevron(path),
        type: "button", class: cn(BTN_BASE, pos),
        "aria-label": label, data: { action: "click->#{action}" })
    end

    def pause_btn
      content_tag(:button, icon(PAUSE_PATH),
        type: "button", class: PAUSE_CLS,
        "aria-label": t("ui.carousel.pause", default: "Pause"),
        data: { carousel_target: "pause",
                action: "click->carousel#toggle",
                label_pause: t("ui.carousel.pause", default: "Pause"),
                label_play: t("ui.carousel.play", default: "Play"),
                icon_pause: PAUSE_PATH, icon_play: PLAY_PATH })
    end

    def dots
      content_tag(:div, class: DOTS_CLS, role: "group",
        "aria-label": t("ui.carousel.pick", default: "Choose slide"),
        data: { carousel_target: "dots" }) do
        safe_join(slides.each_with_index.map { |_, i|
          content_tag(:button, nil, type: "button", class: DOT_CLS,
            "aria-label": t("ui.carousel.go_to", n: i + 1, default: "Go to slide %{n}"),
            "aria-current": i.zero?.to_s,
            data: { action: "click->carousel#goTo", carousel_index_param: i })
        })
      end
    end

    # aria-live=off while rotating; the controller flips it to polite when paused.
    def live_region
      content_tag(:div, "", class: "sr-only", "aria-live": "off", data: { carousel_target: "status" })
    end

    def chevron(path)
      icon(path)
    end

    def icon(path)
      content_tag(:svg,
        content_tag(:path, nil, d: path, "stroke-linecap": "round", "stroke-linejoin": "round"),
        class: "size-5", viewBox: "0 0 24 24", fill: "none",
        stroke: "currentColor", "stroke-width": "2", "aria-hidden": "true")
    end
  end
end

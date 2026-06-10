# frozen_string_literal: true

module UI
  # # QrCode
  #
  # A container for a QR code — a pre-rendered image (`src:`) or raw SVG/HTML from a
  # generator gem such as `rqrcode` (block). A QR code is meaningful content (it
  # encodes a payload), so the wrapper is a single labelled graphic.
  #
  # ## Use when
  # - You need to display a scannable code and already have the image URL or the
  #   gem-generated SVG markup.
  #
  # ## Don't use when
  # - You want decorative imagery — use `image`/`figure`. A QR code always carries a
  #   meaningful name.
  #
  # ## Accessibility contract
  # - **Guarantees:** the wrapper is `role="img"` + `aria-label`, so BOTH the `src:`
  #   image path and the block (raw-SVG) path announce a real name — not a silent,
  #   unlabelled `<svg>` (WCAG 1.1.1 / 4.1.2). The inner `<img>` is decorative
  #   (`alt=""`) so the code is announced once. Caller html_attrs can't strip the name.
  # - **You supply:** an `alt:` that describes what the code encodes, not a bare "QR code".
  # @logical_path Media
  class QrCodeComponentPreview < ViewComponent::Preview
    include UIHelper

    # A pre-rendered QR image with a meaningful accessible name.
    def default
    end

    # Raw inline SVG (as a generator gem like rqrcode emits) — the wrapper names it.
    def block_svg
    end

    # ## Don't — a vague accessible name
    #
    # `alt: "QR code"` tells a screen-reader user nothing about where the code leads.
    # Describe the payload ("QR code linking to example.com") so the name is useful.
    # @label Don't · vague name
    def dont_vague_name
    end
  end
end

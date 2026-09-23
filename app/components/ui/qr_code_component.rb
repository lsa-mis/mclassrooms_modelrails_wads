# frozen_string_literal: true

module UI
  # A container that renders a QR code — either a pre-rendered image (`src:`) or raw SVG/HTML from a generator gem such as `rqrcode` (block).
  # Usage, options and the accessibility contract: docs/components/qr_code.md in the
  # modelrails_ui gem (`bundle show modelrails_ui`); live examples in Lookbook.
  class QrCodeComponent < ApplicationComponent
    # bg-surface (a semantic token, not raw `bg-white`) + p-3 quiet zone keeps the
    # code on a light, high-contrast field that scanners need, in both themes.
    WRAPPER_CLS = "inline-flex items-center justify-center overflow-hidden rounded-lg bg-surface p-3"

    def initialize(src: nil, alt: nil, size: 200, **html_attrs)
      @src = src
      @alt = alt.presence || I18n.t("modelrails_ui.qr_code.label", default: "QR code")
      @size = size
      @extra_class = html_attrs.delete(:class)
      @html_attrs = html_attrs
    end

    def call
      content_tag(:div, **wrapper_attrs) do
        if @src
          # The wrapper carries the accessible name; the <img> is decorative so AT
          # announces the code once, not twice.
          tag.img(src: @src, alt: "", width: @size, height: @size,
            class: "block", loading: "lazy")
        else
          content
        end
      end
    end

    private

    # Caller html_attrs merge FIRST; role/aria-label apply as overrides so a caller
    # can't strip the accessible name off the labelled graphic.
    def wrapper_attrs
      attrs = {}
      @html_attrs.each { |k, v| attrs[k.to_s] = v }
      attrs["class"] = cn(WRAPPER_CLS, @extra_class)
      attrs["role"] = "img"
      attrs["aria-label"] = @alt
      attrs
    end
  end
end

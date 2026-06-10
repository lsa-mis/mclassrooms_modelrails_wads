# frozen_string_literal: true

module UI
  # # DeviceMockup
  #
  # A decorative device frame — phone, tablet, or browser window — that wraps any
  # content. The CHROME (bezel, notch, traffic-light dots, address bar) is purely
  # presentational and `aria-hidden`; the slotted CONTENT carries its own a11y.
  #
  # ## Use when
  # - Showing a product screenshot or demo inside a recognizable device shell.
  #
  # ## Don't use when
  # - The frame would imply interactivity the static content doesn't have.
  #
  # ## Accessibility contract
  # - **Guarantees:** plain `<div>` wrapper (no bogus role), every decorative chrome
  #   bit is `aria-hidden`, and AAA semantic tokens throughout (no raw palette).
  # - **You supply:** the framed content with its own a11y — real `alt` text on a
  #   meaningful screenshot, or `alt: ""` for a decorative one.
  # @logical_path Media
  class DeviceMockupComponentPreview < ViewComponent::Preview
    include UIHelper

    # Portrait phone frame with a decorative top notch (default).
    def phone
    end

    # Browser window with decorative traffic-light dots and a fake address bar.
    def browser
    end

    # ## Don't — a meaningful screenshot with no alt text
    #
    # The frame is decorative, but the slotted image is real content. Leaving it
    # without `alt` (or `alt: ""` on a meaningful image) hides it from AT. Supply
    # real `alt` text — or `alt: ""` only when the image is genuinely decorative.
    # @label Don't · content image no alt
    def dont_decorative_image_no_alt
    end

    # Edit `variant` live to switch the device frame (phone/browser/tablet).
    # @param variant select [phone, browser, tablet]
    def playground(variant: :browser)
      ui :device_mockup, variant: variant.to_sym, url: "https://example.com/dashboard", class: "max-w-md" do
        '<div class="flex aspect-video items-center justify-center bg-surface-sunken text-sm text-text-body">Screen content</div>'.html_safe
      end
    end
  end
end

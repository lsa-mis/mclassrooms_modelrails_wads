# frozen_string_literal: true

module UI
  # # Gallery
  #
  # A responsive image grid. With `lightbox: true` (default) each cell is a
  # focusable `<button>` that opens a single shared native `<dialog>` (the reused
  # `modal` controller — focus-trap / Escape / restore for free). The `gallery`
  # controller swaps the dialog image's `src`/`alt` before `modal#open` runs.
  #
  # ## Accessibility contract
  # - **Guarantees:** each enlargeable cell is a real `<button>` with an i18n
  #   accessible name ("Enlarge %{alt}") and the `focus-ring` utility; the lightbox
  #   is a native focus-trapped `<dialog>` with an accessible close button.
  # - **You supply:** a non-blank `alt:` per image when lightbox is on (fail-loud).
  # @logical_path Media
  class GalleryComponentPreview < ViewComponent::Preview
    include UIHelper

    # A 3-up lightbox grid. Click (or keyboard-activate) any cell to enlarge it.
    def default
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe UI::GalleryComponent, type: :component do
  # Task 11: the grid cell renders a small rendition while the lightbox opens a
  # larger one. `full_src:` feeds the dialog swap (`data-gallery-src-param`)
  # without touching the cell <img>, so the 200px thumb is never upscaled to
  # max-h-[90vh].
  it "sends full_src to the lightbox param while the cell img keeps src" do
    render_inline(described_class.new) do |g|
      g.with_image(src: "/thumb-a.webp", full_src: "/full-a.webp", alt: "Photo A")
    end

    expect(page).to have_css(%(button[data-gallery-src-param="/full-a.webp"]))
    expect(page).to have_css(%(img[src="/thumb-a.webp"]))
    expect(page).not_to have_css(%(img[src="/full-a.webp"]))
  end

  # Pins the pre-Task-11 behaviour: with no full_src the lightbox falls back to
  # the same src the cell renders.
  it "falls back to src for the lightbox param when full_src is absent" do
    render_inline(described_class.new) do |g|
      g.with_image(src: "/thumb-b.webp", alt: "Photo B")
    end

    expect(page).to have_css(%(button[data-gallery-src-param="/thumb-b.webp"]))
  end
end

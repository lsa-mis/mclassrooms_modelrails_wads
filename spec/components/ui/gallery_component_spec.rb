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

  # modelrails_ui v0.8.0 sync: with 2+ images the lightbox gains prev/next nav
  # and a counter bar (caption + count targets) so viewers can page through
  # the set without closing and reopening the dialog.
  it "renders lightbox nav buttons and the caption/count targets with 2+ images" do
    render_inline(described_class.new) do |g|
      g.with_image(src: "/a.webp", alt: "Photo A")
      g.with_image(src: "/b.webp", alt: "Photo B")
    end

    expect(page).to have_css(%(button[data-action="click->gallery#prev"]))
    expect(page).to have_css(%(button[data-action="click->gallery#next"]))
    expect(page).to have_css(%(dialog [data-gallery-target="caption"]))
    expect(page).to have_css(%(dialog [data-gallery-target="count"]))
  end

  # With a single image there is nothing to page through, so no nav renders.
  it "renders no lightbox nav with a single image" do
    render_inline(described_class.new) do |g|
      g.with_image(src: "/a.webp", alt: "Photo A")
    end

    expect(page).not_to have_css(%(button[data-action="click->gallery#prev"]))
    expect(page).not_to have_css(%(button[data-action="click->gallery#next"]))
    expect(page).not_to have_css(%(dialog [data-gallery-target="count"]))
  end

  # LightboxComponent is standalone-renderable so bespoke consumers (e.g. a
  # media stage) can place it next to their own triggers.
  it "renders LightboxComponent standalone as a dialog with nav when count > 1" do
    render_inline(described_class::LightboxComponent.new(count: 3))

    expect(page).to have_css("dialog")
    expect(page).to have_css(%(button[data-action="click->gallery#next"]))
  end
end

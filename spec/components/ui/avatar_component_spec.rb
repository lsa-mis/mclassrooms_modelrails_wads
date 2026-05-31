# frozen_string_literal: true

require "rails_helper"

# Parity: gem Avatar reproduces the app's avatar presentation (AvatarHelper::AVATAR_SIZES,
# rounded-full, hue initials). avatar_for keeps the model logic (source/AS/gravatar) and
# renders this component.
RSpec.describe UI::AvatarComponent, type: :component do
  it "renders an image avatar (rounded-full object-cover, app size, aria-hidden default)" do
    render_inline(described_class.new(src: "/a.png", size: :lg))
    img = page.find("img")
    expect(img[:class]).to include("w-16")
    expect(img[:class]).to include("h-16")
    expect(img[:class]).to include("rounded-full")
    expect(img[:class]).to include("object-cover")
    expect(img["aria-hidden"]).to eq("true")
  end

  it "renders initials with the default interactive color" do
    render_inline(described_class.new(fallback: "JD", size: :md))
    span = page.find("span")
    expect(span.text).to eq("JD")
    expect(span[:class]).to include("w-10")
    expect(span[:class]).to include("bg-interactive")
    expect(span[:class]).to include("text-text-on-interactive")
    expect(span[:class]).to include("rounded-full")
    expect(span[:class]).to include("font-semibold")
  end

  it "renders initials with a custom hue" do
    render_inline(described_class.new(fallback: "JD", hue: 280))
    span = page.find("span")
    expect(span[:class]).to include("bg-hue-initials")
    expect(span[:style]).to include("--hue: 280")
  end

  it "uses aria-label when provided (interactive context)" do
    render_inline(described_class.new(fallback: "JD", aria_label: "Jane Doe"))
    expect(page).to have_css('span[aria-label="Jane Doe"]')
  end
end

require "rails_helper"

RSpec.describe "Brand alignment" do
  let(:brand_css) { Rails.root.join("app/assets/tailwind/tokens/_brand.css").read }

  def primary(shade)
    match = brand_css.match(/--primary-#{shade}:\s*oklch\(\s*([\d.]+)%\s+([\d.]+)\s+([\d.]+)\s*\)/)
    raise ArgumentError, "no oklch --primary-#{shade} in _brand.css" unless match

    match.captures.map(&:to_f)
  end

  def srgb_hex(lightness, chroma, hue)
    channels = ContrastMath.oklch_to_rgb(lightness, chroma, hue).map do |linear|
      encoded = linear <= 0.0031308 ? 12.92 * linear : (1.055 * (linear**(1 / 2.4))) - 0.055
      (encoded * 255).round.clamp(0, 255)
    end
    format("#%02x%02x%02x", *channels)
  end

  it "uses the brand's hue as the default identity hue" do
    expect(Identity::DEFAULT_HUE).to eq(primary(900).last.round)
  end

  it "defaults new workspaces and users to that hue" do
    expect(Workspace.new.primary_color).to eq(Identity::DEFAULT_HUE)
    expect(User.new.primary_color).to eq(Identity::DEFAULT_HUE)
  end

  it "colors email buttons and links with the brand's interactive shade" do
    expect(MailerTheme::INTERACTIVE).to eq(srgb_hex(*primary(800)))
  end
end

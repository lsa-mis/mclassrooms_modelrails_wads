require "rails_helper"

# Rails 8.1.3.1 (GHSA-xr9x-r78c-5hrm) calls Vips.block_untrusted(true) at boot,
# which makes libvips refuse the loaders it flags as unsafe for untrusted input.
# Three of Rails' default variable_content_types use those loaders, so a variant
# request for them raises Vips::Error. config/initializers/active_storage.rb
# drops them from the variable list; these examples pin both halves of that —
# the types that must be gone, and the ones that must stay.
RSpec.describe "Active Storage variant safety" do
  blocked_loader_types = %w[
    image/bmp
    image/vnd.microsoft.icon
    image/vnd.adobe.photoshop
  ].freeze

  # Verified against libvips 8.18.4 under Vips.block_untrusted(true): each of
  # these still loads and thumbnails. Do not prune them.
  safe_loader_types = %w[
    image/png
    image/jpeg
    image/gif
    image/webp
    image/tiff
    image/avif
    image/heic
    image/heif
  ].freeze

  it "does not treat blocked-loader types as variable" do
    expect(ActiveStorage.variable_content_types).not_to include(*blocked_loader_types)
  end

  it "still treats every format libvips can safely transform as variable" do
    expect(ActiveStorage.variable_content_types).to include(*safe_loader_types)
  end

  it "reports a blocked-loader blob as neither variable nor representable" do
    blob = ActiveStorage::Blob.new(content_type: "image/bmp", filename: "art.bmp")

    expect(blob.variable?).to be false
    expect(blob.representable?).to be false
  end

  it "keeps generating variants for the allowed avatar and logo formats" do
    blob = ActiveStorage::Blob.new(content_type: "image/png", filename: "avatar.png")

    expect(blob.variable?).to be true
  end

  it "runs against a libvips new enough for Active Storage to secure" do
    require "vips"
    running = Gem::Version.new("#{Vips.version(0)}.#{Vips.version(1)}.#{Vips.version(2)}")

    expect(running).to be >= Gem::Version.new("8.13"),
      "Active Storage raises at boot below libvips 8.13 (GHSA-xr9x-r78c-5hrm)"
    expect(Gem::Version.new(Vips::VERSION)).to be >= Gem::Version.new("2.2.1")
  end
end

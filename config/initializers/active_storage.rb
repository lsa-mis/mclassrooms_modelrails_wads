# Rails 8.1.3.1 blocks untrusted libvips loaders, so variants of exactly these
# three types raise Vips::Error; subtracting them renders the file-chip branch
# instead of a broken <img>. See /docs/developer/security (Image Processing).
Rails.application.config.active_storage.variable_content_types -= %w[
  image/bmp
  image/vnd.microsoft.icon
  image/vnd.adobe.photoshop
]

# What can be UPLOADED (vs. what renders as a variant, above) is gated per
# surface: model validations and DirectUploadsController (SEC-7). Widen there.

# Rails 8.1.3.1 (GHSA-xr9x-r78c-5hrm) disables the libvips loaders and savers
# libvips flags as unsafe for untrusted input, so variant generation for these
# three raises Vips::Error. Action Text attachments carry no content-type
# allowlist, and app/views/active_storage/blobs/_blob.html.erb links the variant
# as an <img> src — processing is lazy, so the page returns 200 and the error
# surfaces as a 500 on the representation request, i.e. a broken image on every
# view. Dropping the types makes Blob#representable? false, so the partial
# renders its file-chip branch instead.
#
# Verified on libvips 8.18.4 under Vips.block_untrusted(true) that every other
# entry in the default list (PNG, JPEG, GIF, WebP, TIFF, AVIF, HEIC, HEIF) still
# loads and transforms — nothing else may be removed here. A fork that needs one
# of these three can re-enable the specific libvips operation instead.
Rails.application.config.active_storage.variable_content_types -= %w[
  image/bmp
  image/vnd.microsoft.icon
  image/vnd.adobe.photoshop
]

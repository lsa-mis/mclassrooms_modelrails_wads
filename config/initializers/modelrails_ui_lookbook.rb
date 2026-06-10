# frozen_string_literal: true

# Lookbook — interactive component explorer / living docs for modelrails_ui (dev-only).
# Mounted at /lookbook (see config/routes.rb). Previews live in spec/components/previews.
# ViewComponent 4 nests preview config under `previews`.
#
# ViewComponent's own previews controller (/rails/view_components) is enabled in
# development AND test so system/request specs can render previews as host pages.
# The Lookbook engine itself stays development-only (see config/routes.rb).
if Rails.env.development? || Rails.env.test?
  vc = Rails.application.config.view_component
  preview_dir = Rails.root.join("spec/components/previews").to_s
  vc.previews.paths = Array(vc.previews.paths) | [ preview_dir ]
  vc.previews.default_layout = "component_preview"

  Rails.application.config.lookbook.preview_paths = [ preview_dir ] if Rails.env.development?
  Rails.application.config.lookbook.page_paths = [ Rails.root.join("spec/components/previews/pages").to_s ] if Rails.env.development?
end

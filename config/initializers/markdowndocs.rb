# frozen_string_literal: true

Markdowndocs.configure do |config|
  # Path to markdown files
  config.docs_path = Rails.root.join("app", "docs")

  # Allow hand-authored inline SVG diagrams in docs. The sanitizer still
  # strips scripts/handlers; see markdowndocs CHANGELOG 0.8.0.
  config.allow_svg = true

  # Category → slug mapping
  # Maps category names to arrays of markdown file slugs (filenames without .md)
  # NOTE: every file in app/docs/ must appear in exactly one category here, or
  # it renders only by direct URL and is invisible on the /docs index.
  # spec/docs/index_coverage_spec.rb fails CI if a doc is left orphaned.
  config.categories = {
    "Getting Started" => %w[getting-started],
    # The presets hub + its three per-preset spokes form their own cluster,
    # placed second so it reads as the next step after "getting started".
    "Presets" => %w[presets presets-solo presets-single-tenant presets-open-saas],
    "Architecture" => %w[architecture],
    # `notifications` (audience: guide) and `notifications-technical`
    # (audience: technical) are paired companion docs — the mode switcher
    # shows whichever matches the viewer's mode, with no cross-category
    # split. Listing both here keeps the topic discoverable from the
    # canonical "Features" category in either mode.
    "Features" => %w[accounts workspaces projects identity-system emails notifications notifications-technical],
    "Guides" => %w[extending security ui-patterns deployment background-jobs troubleshooting]
  }

  # Available documentation modes (default: %w[guide technical])
  # config.modes = %w[guide technical]

  # Default mode (default: "guide")
  # config.default_mode = "guide"

  # Rouge syntax highlighting theme (default: "github")
  # config.rouge_theme = "github"

  # Cache expiry for rendered markdown (default: 1.hour)
  # config.cache_expiry = 1.hour

  # Enable full-text search on the documentation index (default: false)
  # Adds a search bar that filters docs by title, description, and content
  config.search_enabled = true

  # Resolve the current user's mode preference from the database.
  # `user_preferences.docs_mode` is the canonical source of truth; cookie
  # fallback (handled by the gem) covers signed-out visitors and first-time
  # users. Returning nil lets the gem fall back to cookie → default.
  config.user_mode_resolver = ->(controller) {
    controller.send(:current_user)&.preferences&.docs_mode
  }

  # Persist the user's mode pick to the same column. The
  # `preferences || create_preferences!` pattern guarantees the saver works
  # even for users who don't have a preferences row yet (first-time
  # mode-switchers) — without this the update! call would silently no-op
  # via the `&.` safe-navigation, leaving the choice cookie-only.
  config.user_mode_saver = ->(controller, mode) {
    user = controller.send(:current_user)
    next unless user
    prefs = user.preferences || user.create_preferences!
    prefs.update!(docs_mode: mode)
  }
end

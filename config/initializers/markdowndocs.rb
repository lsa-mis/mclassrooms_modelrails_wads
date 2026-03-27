# frozen_string_literal: true

Markdowndocs.configure do |config|
  # Path to markdown files (default: Rails.root.join("app/docs"))
  # config.docs_path = Rails.root.join("app", "docs")

  # Category → slug mapping
  # Maps category names to arrays of markdown file slugs (filenames without .md)
  config.categories = {
    "Getting Started" => %w[getting-started],
    "Architecture" => %w[architecture],
    "Guides" => %w[extending security]
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
  # config.search_enabled = true

  # Optional: Resolve current user's mode preference from database
  # Return nil to fall back to cookie/default
  # config.user_mode_resolver = ->(controller) {
  #   controller.send(:current_user)&.preferences&.docs_mode
  # }

  # Optional: Save user's mode preference to database
  # config.user_mode_saver = ->(controller, mode) {
  #   controller.send(:current_user)&.preferences&.update!(docs_mode: mode)
  # }
end

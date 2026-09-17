require "rails_helper"

# Two navigation facts changed in 2026-09 and the docs kept describing the old
# ones: the workspace switcher left the header for the sidebar and, on phones,
# the content column above the section tabs (#1078, #1089); and `/me` was
# folded into `/workspaces`, which opens with who "you" are. Patterns are as
# narrow as auth_docs_accuracy_spec's — "header" and "switcher" co-occur
# legitimately (the docs-mode switcher), so only the phrases the stale docs
# actually used are matched.
RSpec.describe "Navigation docs accuracy", type: :model do
  docs = Rails.root.join("app/docs")
  pages = Dir[docs.join("**/*.md")]

  it "has no /me route to document" do
    expect { Rails.application.routes.recognize_path("/me") }.to raise_error(ActionController::RoutingError)
  end

  it "names no page as /me" do
    offenders = pages.select { |f| File.read(f).match?(%r{(?<![\w/])/me(?![\w/.-])}) }
    expect(offenders).to be_empty, "stale /me refs in: #{offenders.map { |f| File.basename(f) }.join(', ')}"
  end

  it "does not place the workspace switcher in the header or the hamburger" do
    pattern = /header (workspace )?switcher|switcher (lives|renders) (inside|in) the hamburger/i
    offenders = pages.select { |f| File.read(f).match?(pattern) }
    expect(offenders).to be_empty, "switcher described in the header/hamburger in: #{offenders.map { |f| File.basename(f) }.join(', ')}"
  end
end

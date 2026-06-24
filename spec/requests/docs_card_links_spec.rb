require "rails_helper"
require "nokogiri"

# Regression: the docs index cards must link to each doc's canonical
# mode-scoped path (/docs/<mode>/<slug>), NOT the bare /docs/<slug>.
#
# Under markdowndocs path-based audience routing a slug lives in exactly one
# mode, so a bare /docs/<slug> resolves only in that mode. Landing on a bare
# URL and then switching audience leaves you on a URL that 404s — the gem's
# smart_nav_target "stays put" on the bare path. Linking the scoped path keeps
# every card-driven navigation on a URL that resolves in any mode.
RSpec.describe "Docs index card links", type: :request do
  it "links cards to the canonical mode-scoped path, not the bare slug" do
    get "/docs", params: { mode: "developer" }
    expect(response).to have_http_status(:ok)

    hrefs = Nokogiri::HTML(response.body).css("a").map { |a| a["href"] }

    # The developer index shows the presets doc; its card must point at the
    # scoped path, and the bare slug must NOT appear as a link target.
    expect(hrefs).to include("/docs/developer/presets")
    expect(hrefs).not_to include("/docs/presets")
  end
end

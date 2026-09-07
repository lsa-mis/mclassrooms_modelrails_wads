# frozen_string_literal: true

require "rails_helper"

# A bearer token in a URL path segment is written verbatim into every request
# log line: `config.filter_parameters` reaches query strings and form fields,
# never path segments. The existing routes below are an accepted, documented
# exposure (#916, app/docs/developer/security.md "Bearer Tokens in Request
# Logs"); new work puts secrets in the query string or the body. This fence
# holds the set to the decision instead of letting it drift by one route at a
# time.
RSpec.describe "No new bearer tokens in route paths" do
  # Each entry names the decision that keeps it here.
  accepted = {
    "/magic_link_callback/:token(.:format)"                     => "#916: 15-minute single-use token; GET confirms, POST consumes",
    "/magic_link_callback/:magic_link_callback_token/session(.:format)" => "#916: same token; the nested session's consuming POST",
    "/invitations/:token/accept(.:format)"                      => "#916: 7-day single-use token, email-matched on accept",
    "/invitations/:token/decline(.:format)"                     => "#916: 7-day token; identity guard tracked in #951",
    "/workspaces/:workspace_slug/joins/:token(.:format)"        => "#916: shareable by design; expiry tracked in #952",
    "/settings/connected_accounts/verify/:token(.:format)"      => "#950: legacy alias, remove after the 2026-09 deploy plus one day",
    "/rails/active_storage/disk/:encoded_token(.:format)"       => "Active Storage engine: 5-minute signed direct-upload token"
  }.freeze

  def token_route_specs
    specs = []
    walk = lambda do |route_set|
      route_set.routes.each do |route|
        specs << route.path.spec.to_s
        app = route.app.respond_to?(:app) ? route.app.app : route.app
        walk.call(app.routes) if app.respond_to?(:routes) && app.routes.respond_to?(:routes) && app != Rails.application
      end
    end
    walk.call(Rails.application.routes)
    specs.uniq.select { |spec| spec.match?(/:[a-z_]*token\b/) }.sort
  end

  it "keeps every token-bearing path segment on the accepted list" do
    unlisted = token_route_specs - accepted.keys

    expect(unlisted).to be_empty,
      "New route(s) carry a bearer token in a path segment, where every request log records it verbatim. " \
      "Put the secret in the query string or the request body instead (#916):\n  #{unlisted.join("\n  ")}"
  end

  it "drops accepted entries whose route no longer exists, so the list stays a decision and not a fossil" do
    gone = accepted.keys - token_route_specs

    expect(gone).to be_empty, "Accepted routes that no longer exist; remove them:\n  #{gone.join("\n  ")}"
  end
end

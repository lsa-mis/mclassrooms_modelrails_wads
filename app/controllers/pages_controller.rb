# Fork-owned (merge=ours): MiClassrooms marketing/static pages. Per the
# design spec (Brief §3.2), #home and #about are the product's only two
# unauthenticated pages — the public landing (with a sign-in CTA) and the
# About page. #privacy/#contact stay reachable unauthenticated for now
# (template defaults); a later phase revisits whether they belong behind
# sign-in once the shared-tenancy/SSO posture lands.
class PagesController < ApplicationController
  allow_unauthenticated_access

  def home
  end

  def about
  end

  def privacy
  end

  def contact
  end
end

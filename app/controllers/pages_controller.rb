# Fork-owned (merge=ours): MiClassrooms marketing/static pages. Per the
# design spec (Brief §3.2), #home and #about are the product's only two
# unauthenticated pages — the public landing (with a sign-in CTA) and the
# About page. #privacy/#contact stay reachable unauthenticated for now
# (template defaults); a later phase revisits whether they belong behind
# sign-in once the shared-tenancy/SSO posture lands.
class PagesController < ApplicationController
  allow_unauthenticated_access

  # The landing renders for EVERYONE — anonymous, viewer, admin (panel call,
  # 2026-07-13, retiring Phase 3 Task 6's non-admin redirect). The header
  # logo links to root, and a link named for the site must mean the same
  # thing for every role. "Signed-in users start in the product" still holds,
  # but it's decided once at sign-in (ApplicationController#
  # authenticated_home_path — the template's seam), not by hijacking root on
  # every visit. This also un-hides the home_page announcement slot from
  # viewers, who previously could never reach it; the view swaps the sign-in
  # CTAs for Find-a-Room ones when authenticated.
  def home
    @announcement = Announcement.for(:home_page)
  end

  # Phase 5 Task 8 (Brief §14.1): the about_page announcement slot, rendered
  # through the same shared announcements/_banner partial as home/find-a-room
  # (Announcement.for is a deliberate GLOBAL find_by — see app/models/
  # announcement.rb — so no workspace context is required here, unlike the
  # authenticated product pages).
  def about
    @announcement = Announcement.for(:about_page)
  end

  def privacy
  end

  def contact
  end
end

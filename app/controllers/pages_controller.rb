# Fork-owned (merge=ours): MiClassrooms marketing/static pages. Per the
# design spec (Brief §3.2), #home and #about are the product's only two
# unauthenticated pages — the public landing (with a sign-in CTA) and the
# About page. #privacy/#contact stay reachable unauthenticated for now
# (template defaults); a later phase revisits whether they belong behind
# sign-in once the shared-tenancy/SSO posture lands.
class PagesController < ApplicationController
  allow_unauthenticated_access

  # Phase 3 Task 6 (Brief §5.1): signed-in non-admins land on Find a Room
  # instead of the marketing homepage; admins and anonymous visitors keep
  # the landing page. Redirects only when TenancyConfig.shared_workspace
  # is admittable (kept + not suspended) — the same gate DirectoryScoped
  # uses to admit GET /find-a-room — so a suspended (or missing/personal-
  # posture) shared workspace never bounces a viewer between root_path and
  # find_a_room_path (DirectoryScoped redirects a suspended workspace back
  # to root_path, which would otherwise loop forever).
  def home
    @announcement = Announcement.for(:home_page)

    return unless authenticated? # home allows unauthenticated access; resume the session explicitly
    return if RoleResolver.for(Current.user).admin? # admins keep the landing page

    workspace = TenancyConfig.shared_workspace # nil unless shared posture + kept workspace exists
    redirect_to find_a_room_path if workspace && !workspace.suspended?
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

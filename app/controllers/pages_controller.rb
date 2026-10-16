class PagesController < ApplicationController
  allow_unauthenticated_access

  PAGES = %w[home about privacy contact].freeze
  ANNOUNCEMENT_SLOTS = { "home" => :home_page, "about" => :about_page }.freeze

  def show
    raise ActionController::RoutingError, "No page #{params[:id].inspect}" unless PAGES.include?(params[:id])

    slot = ANNOUNCEMENT_SLOTS[params[:id]]
    @announcement = Announcement.for(slot) if slot
    render params[:id]
  end
end

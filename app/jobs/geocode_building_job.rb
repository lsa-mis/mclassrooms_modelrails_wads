# Enqueued by Sync::UpdateBuildings for every newly-created building (Task 8
# of planning/plans/phase-2-ingestion.md; roadmap Lib section) — never for
# an update, so a building's coordinates are only ever looked up once.
#
# Current.workspace: Building is Tenanted, and Tenanted installs no
# default_scope (app/docs/developer/extending.md), so nothing scopes this
# job's queries automatically. Per the template's job rule (CLAUDE.md
# deviation #1 — "jobs must establish workspace context explicitly"), this
# sets Current.workspace itself before doing anything workspace-scoped,
# rather than assuming a job runner has any ambient request context.
#
# Skip-if-already-geocoded: `perform_later` can retry or, in principle, be
# enqueued twice for the same building, so this checks both coordinates
# before ever calling out to Geocoder — a re-run is a no-op, not a
# clobber of a previously (possibly manually corrected) location.
#
# Retry: Geocoder swallows most transient lookup failures internally and
# returns an empty result set (Geocoder::Lookup::Base#fetch_data only
# raises Geocoder::Error/Geocoder::LookupTimeout when explicitly configured
# via `always_raise`) — so `retry_on` here is a safety net for that
# opt-in configuration and for a bare network Timeout::Error, not the
# common case.
class GeocodeBuildingJob < ApplicationJob
  queue_as :default
  retry_on Geocoder::Error, Timeout::Error, wait: :exponentially_longer, attempts: 3

  def perform(building_id)
    building = Building.find(building_id)
    Current.workspace = building.workspace

    return if building.latitude.present? && building.longitude.present?

    result = Geocoder.search(building.full_address).first
    return unless result

    building.update!(latitude: result.latitude, longitude: result.longitude)
  end
end

# Campus sync — Task 7 of planning/plans/phase-2-ingestion.md (roadmap Lib
# section). The FIRST concrete Sync::BasePhase subclass, and the shape the
# remaining five phases (buildings, rooms, facility_ids, characteristics,
# contacts — Tasks 8-11) are expected to mirror.
#
# Hard delete (Brief §6.1 phase 1): campuses are the ONE hard-delete in the
# whole sync. Every other phase only ever deactivates or updates a record
# that drops out of its feed; a campus that disappears is genuinely retired
# by U-M, so it's destroyed outright. That's also why only the destroy is
# wrapped in `guarded_write` below — the create/update upsert is an
# idempotent refresh, not the destructive action dry-run exists to preview,
# so it runs unconditionally (mirrors BasePhase's contract: subclasses guard
# only the destructive write, never the routine one).
#
# Current.workspace / Tenanted: Campus is Tenanted, and Tenanted installs no
# default_scope (app/docs/developer/extending.md) — scoping is explicit, not
# ambient magic. In production the pipeline job (Task 12) sets
# Current.workspace before invoking any phase, the same way every other
# Tenanted write path in this app works; #perform below relies on that and
# scopes every Campus query through `.for_current_workspace`. That does two
# things at once: (1) an existing campus is only ever matched within this
# run's tenant, so a stale-record sweep can never reach into another
# workspace's data, and (2) find_or_initialize_by's `scope_for_create` stamps
# workspace_id onto brand-new records for free (verified empirically — see
# task-7-report.md).
#
# parse_campus(row) isolation: per spec/support/um_api_stubs.rb's fixture
# disclaimer, the real Campuses endpoint's field names haven't been
# confirmed against credentialed access. CampusCd/CampusDescr here match
# spec/fixtures/um_api/campuses.json exactly; if phase 8's live cutover finds
# different names, this is the ONLY method that needs to change — no other
# code reaches into a raw API response hash directly.
module Sync
  class UpdateCampuses < BasePhase
    KEY = "campuses"

    private

    def perform
      seen = []

      client.each_page("/bf/Buildings/v2/Campuses", scope: "buildings") do |row|
        attrs = parse_campus(row)
        seen << attrs[:code]

        campus = Campus.for_current_workspace.find_or_initialize_by(code: attrs[:code])
        campus.new_record? ? count(:created) : (count(:updated) if campus.changed_after_assign(attrs))
        campus.update!(attrs)
      end

      Campus.for_current_workspace.where.not(code: seen).find_each do |stale|
        count(:deleted)
        guarded_write { stale.destroy! }
      end
    end

    def parse_campus(row) = { code: row.fetch("CampusCd").to_s, description: row.fetch("CampusDescr") }
  end
end

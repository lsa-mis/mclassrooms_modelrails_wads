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
# parse_campus(row) isolation: CampusCd/CampusDescr are confirmed against
# live credentialed access (sync-fix Task 2; see the proven reference
# `lib/tasks/um_import.rake#import_campuses`) — no other code reaches into a
# raw API response hash directly, so a future field-name change (unlikely;
# this endpoint is already verified) would still only touch this one method.
#
# Listing call: `client.fetch_all(...)` (UmApi::Client, sync-fix Task 1)
# replaces the old `each_page` — it pages via the real `$start_index`/
# `$count` params and digs the real two-level envelope
# (`resp["Campuses"]["Campus"]`) instead of `each_page`'s unverified `limit`
# param and single-level auto-detected array.
module Sync
  class UpdateCampuses < BasePhase
    KEY = "campuses"

    private

    def perform
      seen = []

      rows = client.fetch_all("/bf/Buildings/v2/Campuses", array_path: %w[Campuses Campus], scope: "buildings")

      rows.each do |row|
        attrs = parse_campus(row)
        seen << attrs[:code]

        campus = Campus.for_current_workspace.find_or_initialize_by(code: attrs[:code])
        campus.new_record? ? count(:created) : (count(:updated) if campus.changed_after_assign(attrs))
        campus.update!(attrs)
      end

      delete_stale_campuses(seen)
    end

    # The stale-campus sweep — deliberately resilient (Brief §9: never corrupt
    # local data, produce a comprehensive run report). Two guards distinguish
    # this from the naive "destroy everything not in `seen`":
    #
    # 1. Empty-seen guard. An empty `seen` means the feed returned zero rows.
    #    That is far more likely a transient gateway glitch than "the
    #    university retired every campus at once", so treating it as the latter
    #    would wipe the whole table. Skip the sweep entirely and warn.
    #
    # 2. FK-safe per-record delete. Campuses sync BEFORE buildings, so a
    #    campus that dropped out of the feed still has last run's buildings
    #    pointing at it (buildings.campus_id FK, enforced by SQLite) — the
    #    NORMAL retirement case, not an edge case. A raw `destroy!` would raise
    #    ActiveRecord::InvalidForeignKey, abort #perform, and (via BasePhase)
    #    fail the phase, which halts Task 12's whole pipeline. Instead each
    #    delete is independently rescued: a still-referenced campus is
    #    skipped-with-warning and the sweep moves on. Per-record granularity is
    #    the right unit here (individual hard-deletes) — no surrounding
    #    transaction, unlike the rooms phase's UPDATE-deactivation sweep.
    #
    # count(:deleted) reflects only ACTUAL deletions on a real run: it is
    # incremented AFTER destroy! succeeds, never before, so a skipped
    # (still-referenced) campus never inflates it. Under dry-run nothing is
    # destroyed, but every stale campus is counted as a PREVIEW of intent so
    # the report still says how many *would* be deleted. `guarded_write`
    # doesn't cleanly express this split (its count sits outside the guard,
    # which would double-count on a real-run skip), so the dry-run branch is
    # explicit here.
    def delete_stale_campuses(seen)
      if seen.empty?
        add_warning("Campuses feed returned zero rows; skipping stale-campus deletion")
        return
      end

      Campus.for_current_workspace.where.not(code: seen).find_each do |stale|
        if dry_run?
          count(:deleted)
          next
        end

        begin
          stale.destroy!
          count(:deleted)
        rescue ActiveRecord::InvalidForeignKey
          add_warning("Campus #{stale.code} is still referenced and was not deleted")
        end
      end
    end

    def parse_campus(row) = { code: row.fetch("CampusCd").to_s, description: row.fetch("CampusDescr") }
  end
end

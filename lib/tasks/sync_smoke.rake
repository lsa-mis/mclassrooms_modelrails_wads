# frozen_string_literal: true

# DEV-ONLY live smoke test for the FIXED Sync::* pipeline (sync-fix Task 5).
# Tasks 1-4 migrated all six Sync::BasePhase subclasses + UmApi::Client onto
# the real U-M gateway shapes (see .superpowers/sdd/sync-fix-plan.md and
# sync-fix-decisions.md) — the spec suite proves the mechanics against
# WebMock fixtures, but only a REAL run against the live gateway proves the
# fix actually works end to end, phase-to-phase handoffs included. This task
# is the `Sync::RunPipeline` counterpart to `lib/tasks/um_import.rake`
# (UmImport) — same credential-bridge pattern, same small default 7-building
# scope already validated live by that task (see
# .superpowers/sdd/um-import-report.md) — but drives the actual application
# pipeline (app/lib/sync/*) instead of the standalone UmImport recipe, so
# this is the first live proof that the FIXED sync phases (not just the
# separately-proven reference importer) pull real data end to end.
#
# Scope is intentionally the same small 7 buildings um_import.rake validates
# against (no campus_allow) so the run finishes in a few minutes rather than
# tripping the gateway's rate limit at full-campus scale.
namespace :sync do
  desc "Live smoke test: run the fixed Sync::RunPipeline against the real U-M gateway (dev only; see .superpowers/sdd/um-import-report.md for the known-good baseline to diff against)"
  task smoke: :environment do
    SyncSmoke.run!
  end
end

# Namespaced outside app/ (throwaway dev tooling, not application code) so
# nothing here is autoloaded/eager-loaded in test/production — mirrors
# UmImport's own rationale in lib/tasks/um_import.rake.
module SyncSmoke
  BASE_URL = "https://gw.api.it.umich.edu/um"
  TOKEN_URL = "#{BASE_URL}/oauth2/token"

  WORKSPACE_SLUG = "sync-smoke"

  # The same default 7-building scope lib/tasks/um_import.rake validated
  # live (.superpowers/sdd/um-import-report.md) — no campus_allow, so this
  # stays a small, fast, rate-limit-safe run.
  BUILDING_ALLOW = %w[1000440 1000234 1000204 1000333 1005224 1005059 1005347].freeze
  BUILDING_EXCLUDE = %w[1000890].freeze

  module_function

  def run!
    abort "sync:smoke only runs in development (current env: #{Rails.env})" unless Rails.env.development?

    bridge_credentials!
    workspace = find_or_create_workspace!
    Current.workspace = workspace
    ensure_scope_rules!(workspace)

    puts "[sync:smoke] workspace=#{workspace.slug} building_allow=#{BUILDING_ALLOW.inspect} building_exclude=#{BUILDING_EXCLUDE.inspect}"
    puts "[sync:smoke] running Sync::RunPipeline (dry_run: false) against the LIVE gateway — this makes ~300 real HTTP calls for 7 buildings, budget a few minutes..."

    run = Sync::RunPipeline.call(dry_run: false)

    print_phase_results(run)
    print_counts(workspace)
  end

  # === Credential bridge (in-process only — mirrors UmImport.bridge_credentials! exactly) ===

  def bridge_credentials!
    ENV["UM_API_TOKEN_URL"] = TOKEN_URL
    ENV["UM_API_BASE_URL"] = BASE_URL
    credentials = Rails.application.credentials.um_api
    ENV["UM_API_CLIENT_ID"] = credentials.buildings_client_id.to_s
    ENV["UM_API_CLIENT_SECRET"] = credentials.buildings_client_secret.to_s
  end

  # === Workspace + scope setup (idempotent — safe to re-run) ===

  # Workspace itself needs no Role to exist (Role is an independent,
  # optional-`workspace_id` model — `Sync::RunPipeline`/its six phases never
  # touch Memberships or Roles at all), so none are created here; only a
  # bare Workspace + its SyncScopeRules are required for the pipeline to run.
  def find_or_create_workspace!
    Workspace.find_or_create_by!(slug: WORKSPACE_SLUG) do |workspace|
      workspace.name = "Sync Smoke"
    end
  end

  # Building-allow/exclude rules only (no campus_allow) — find_or_create_by
  # keeps re-running this task idempotent (no duplicate rule rows).
  def ensure_scope_rules!(workspace)
    BUILDING_ALLOW.each do |bldrecnbr|
      SyncScopeRule.for_current_workspace.find_or_create_by!(rule_type: "building_allow", value: bldrecnbr)
    end
    BUILDING_EXCLUDE.each do |bldrecnbr|
      SyncScopeRule.for_current_workspace.find_or_create_by!(rule_type: "building_exclude", value: bldrecnbr)
    end
  end

  # === Reporting ===

  def print_phase_results(run)
    puts "[sync:smoke] run ##{run.id} status=#{run.status} finished_at=#{run.finished_at}"

    run.sync_phases.order(:id).each do |phase|
      puts "[sync:smoke] phase=#{phase.key} status=#{phase.status} counters=#{phase.counters}"
      phase.warnings.each { |warning| puts "[sync:smoke]   warning: #{warning}" }
      phase.error_messages.each { |message| puts "[sync:smoke]   FAILURE: #{message}" }
    end
  end

  def print_counts(workspace)
    puts "[sync:smoke] #{workspace.slug} now has:"
    puts "[sync:smoke]   buildings: #{Building.where(workspace: workspace).count}"
    puts "[sync:smoke]   rooms (total, all room types): #{Room.where(workspace: workspace).count}"
    puts "[sync:smoke]   classrooms (Room.classroom subset): #{Room.where(workspace: workspace).classroom.count}"
    puts "[sync:smoke]   floors: #{Floor.where(workspace: workspace).count}"
    puts "[sync:smoke]   units: #{Unit.where(workspace: workspace).count}"
    puts "[sync:smoke]   room_characteristics: #{RoomCharacteristic.where(workspace: workspace).count}"
    puts "[sync:smoke]   room_contacts: #{RoomContact.where(workspace: workspace).count}"
  end
end

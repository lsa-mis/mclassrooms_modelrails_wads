# frozen_string_literal: true

module LegacyImport
  # Checks preconditions, then runs the phases in their fixed order and halts
  # on the first that raises. The phase 8 plan required a completed SyncRun;
  # dev is loaded by um:import and has none, so the precondition is "the
  # workspace has rooms and buildings", and the report's match counts carry
  # the rest.
  #
  # Opens no outer transaction: each record's Curate transaction must be the
  # outermost so a failed room really rolls back. Current.workspace is set
  # because Curation::Apply stamps it on audit rows.
  class Runner
    PHASES = {
      "fields" => [ Fields ],
      "media" => [ BuildingMedia, RoomMedia ],
      "announcements" => [ Announcements ],
      "notes" => [ Notes ]
    }.freeze

    def self.call(export_path:, workspace:, dry_run: false, only: nil)
      new(export_path:, workspace:, dry_run:, only:).call
    end

    def initialize(export_path:, workspace:, dry_run:, only:)
      @export_path, @workspace, @dry_run = export_path, workspace, dry_run
      @only = only.presence || PHASES.keys
    end

    def call
      unknown = @only - PHASES.keys
      return Result.failure("unknown phase(s): #{unknown.join(", ")} — expected #{PHASES.keys.join(", ")}") if unknown.any?
      return Result.failure("workspace #{@workspace.slug} has no rooms or buildings — run the sync first") unless populated?

      export = Export.new(@export_path)
      Current.set(workspace: @workspace) { run(export) }
    rescue Export::Missing => e
      Result.failure(e.message)
    end

    private

    def populated? = Room.exists?(workspace: @workspace) && Building.exists?(workspace: @workspace)

    def run(export)
      actor = Account.resolve(dry_run: @dry_run)
      results = {}
      PHASES.select { |name, _| @only.include?(name) }.values.flatten.each do |service|
        name = service.name.demodulize
        results[name] = service.call(export:, workspace: @workspace, actor:, dry_run: @dry_run)
      rescue StandardError => e
        return Result.failure("#{name} failed: #{e.class}: #{e.message}", results:)
      end
      Result.success(results:)
    end
  end
end

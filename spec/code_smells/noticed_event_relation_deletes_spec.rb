# frozen_string_literal: true

require "rails_helper"

# `noticed_events` is the append-only ledger of what was dispatched. Deleting
# an event cascades to every recipient's notification row through the FK
# (`noticed_notifications.event_id`, on_delete: :cascade), so a relation-level
# delete on Noticed::Event silently empties other people's lists. No shipped
# surface does this; this spec keeps it that way (parent spec §2, promised in
# the lifecycle arc and delivered by PR 5).
#
# Scanned shape: `Noticed::Event` (optionally chained through scopes on the
# same line) followed by delete_all / destroy_all / delete / destroy. A chain
# broken across lines is not seen; widen the pattern rather than working
# around it. The single-line shape is deliberate: `app/models/invitation_block.rb`
# legitimately builds a subquery on `Noticed::Event` whose outer chain ends in
# `.delete_all` on the notifications relation, and a pattern spanning lines
# would flag it; if a multi-line event delete ever needs catching, widen the
# pattern and register that model in `allowed_files` with this reason.
#
# Carve-out, pre-registered: the orphan-pruning job from #811, by class name,
# when it exists. It must prune by NOT EXISTS against noticed_notifications,
# never by the counter cache, which PR 5 left stale on purpose.
RSpec.describe "Code smell: no relation-level deletes of Noticed::Event" do
  # #811's prune, declared here although the single-line pattern cannot see it.
  allowed_files = { "app/jobs/notification_cleanup_job.rb" => "#811's childless-only orphan prune" }.freeze

  it "app/ and lib/ never delete or destroy Noticed::Event rows" do
    pattern = /Noticed::Event\b[^\n;]*\.(?:delete_all|destroy_all|delete|destroy)\b/

    offenders = Dir[Rails.root.join("{app,lib}/**/*.rb")].filter_map do |file|
      relative = file.delete_prefix("#{Rails.root}/")
      next if allowed_files.key?(relative)

      source = without_comments(File.read(file))
      source.each_line.with_index(1).filter_map do |line, number|
        "#{relative}:#{number}" if line.match?(pattern)
      end.presence
    end.flatten

    expect(offenders).to be_empty,
      "Relation-level deletes of Noticed::Event found:\n#{offenders.join("\n")}\n" \
      "An event delete cascades to every recipient's row. Sweep noticed_notifications instead, " \
      "or register a pruning job here by file name with its reason."
  end

  # The entry must keep earning its permission: childlessness is asked of
  # noticed_notifications, never of the deliberately stale notifications_count.
  it "holds every registered file to the rule that earned it the exemption" do
    problems = allowed_files.filter_map do |relative, reason|
      path = Rails.root.join(relative)
      next "#{relative}: registered for #{reason}, but the file is gone" unless path.exist?

      source = without_comments(File.read(path))
      if source.include?("notifications_count")
        "#{relative}: prunes on the stale notifications_count counter cache"
      elsif !source.include?("noticed_notifications") && !source.include?("Noticed::Notification")
        "#{relative}: never asks noticed_notifications which events still have rows"
      end
    end

    expect(problems).to be_empty,
      "a registered exemption no longer describes what the file does:\n  #{problems.join("\n  ")}"
  end
end

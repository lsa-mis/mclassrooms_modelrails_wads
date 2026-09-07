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
  allowed_files = [].freeze   # e.g. "app/jobs/noticed_event_prune_job.rb" (#811)

  it "app/ and lib/ never delete or destroy Noticed::Event rows" do
    pattern = /Noticed::Event\b[^\n;]*\.(?:delete_all|destroy_all|delete|destroy)\b/

    offenders = Dir[Rails.root.join("{app,lib}/**/*.rb")].filter_map do |file|
      relative = file.delete_prefix("#{Rails.root}/")
      next if allowed_files.include?(relative)

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
end

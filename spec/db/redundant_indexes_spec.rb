# frozen_string_literal: true

require "rails_helper"

# SQLite (like every B-tree store) answers a query on `(a)` from an index on
# `(a, b)` — the leading column is a usable prefix. A single-column index that
# is a strict prefix of a surviving composite therefore buys no read and costs
# a write on every INSERT/UPDATE of that column. #691 listed five; this spec
# pins that they are gone AND that the composite each one leaned on is still
# there, so a later migration cannot drop the covering index and quietly leave
# the column unindexed.
RSpec.describe "Redundant single-column indexes" do
  # table => [redundant index dropped, covering index that subsumes it, its columns]
  # A plain local, not a constant: a constant assigned in a describe body lands
  # on Object and clobbers a same-named one in another spec file
  # (spec/code_smells/no_object_level_spec_constants_spec.rb).
  dropped_with_cover = {
    "memberships" => [
      [ "index_memberships_on_user_id", "index_memberships_on_user_id_and_last_accessed_at", %w[user_id last_accessed_at] ]
    ],
    # Fork (MClassrooms): upstream also pins projects, resources and
    # client_accesses here; those tables do not exist in this fork.
    "workspace_join_links" => [
      [ "index_workspace_join_links_on_workspace_id", "index_workspace_join_links_on_workspace_id_and_revoked_at", %w[workspace_id revoked_at] ]
    ],
    "noticed_notifications" => [
      [ "index_noticed_notifications_on_recipient", "index_noticed_notifications_on_recipient_read_created",
        %w[recipient_type recipient_id read_at created_at] ],
      [ "index_noticed_notifications_unread", "index_noticed_notifications_on_recipient_read_created",
        %w[recipient_type recipient_id read_at created_at] ]
    ]
  }.freeze

  let(:connection) { ActiveRecord::Base.connection }

  dropped_with_cover.each do |table, entries|
    entries.each do |dropped, covering, covering_columns|
      it "#{table} no longer carries #{dropped}" do
        expect(connection.indexes(table).map(&:name)).not_to include(dropped)
      end

      it "#{table} still carries #{covering}, which covers the dropped prefix" do
        index = connection.indexes(table).find { |i| i.name == covering }

        expect(index).to be_present
        expect(index.columns).to eq(covering_columns)
      end
    end
  end

  # Not a duplicate: `WHERE revoked_at IS NULL` makes this one a constraint —
  # at most one live join link per workspace — and dropping it would drop the
  # rule, not just an index.
  it "keeps the partial unique index that enforces one active join link per workspace" do
    index = connection.indexes("workspace_join_links")
      .find { |i| i.name == "index_workspace_join_links_unique_active_per_workspace" }

    expect(index).to be_present
    expect(index.columns).to eq(%w[workspace_id])
    expect(index.unique).to be(true)
    expect(index.where).to eq("revoked_at IS NULL")
  end
end

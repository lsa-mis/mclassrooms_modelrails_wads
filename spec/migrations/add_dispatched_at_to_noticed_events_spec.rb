# frozen_string_literal: true

require "rails_helper"
require_relative "../../db/migrate/20260907180000_add_dispatched_at_to_noticed_events"

# The migration already ran for real, so the schema this spec starts from has
# `dispatched_at`. The `before` hook reverses it once to reach the pre-migration
# state, then the example drives up from there. SQLite DDL is transactional, so
# both reversals are undone by RSpec's per-example rollback.
#
# What is under test is the backfill, and it is not cosmetic: every row written
# before this release is unstamped, past the grace window, and carries a
# non-zero `notifications_count` (nothing prunes events, and the cleanup job
# deletes notification rows without touching the counter). Without the
# backfill, the first production sweep re-delivers the app's entire notification
# history — every email, every broadcast, again.
RSpec.describe AddDispatchedAtToNoticedEvents do
  # `inheritance_column = nil`: the table's `type` column is noticed's STI
  # discriminator, and an anonymous shadow class cannot be a superclass of
  # WelcomeNotifier, so writing a row through it raises SubclassNotFound.
  let(:raw_events) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "noticed_events"
      self.inheritance_column = nil
    end
  end
  let(:migration) { described_class.new }

  before { ActiveRecord::Migration.suppress_messages { migration.down } }

  # The per-example rollback restores the table, but not what the classes
  # remember about it — Active Record does not refresh a model's columns on DDL,
  # and a later spec in the same process would read `dispatched_at` through the
  # column-less picture this example installed.
  after do
    ActiveRecord::Base.connection.schema_cache.clear!
    Noticed::Event.reset_column_information
  end

  it "stamps existing rows with their own created_at, so the first sweep re-enqueues nothing" do
    # Two hours old: past the reconciler's grace and well inside its lookback,
    # so an unstamped row here IS swept. That is what makes the backfill the
    # thing under test rather than the lookback bound.
    written_at = 2.hours.ago
    raw_events.reset_column_information
    event = raw_events.create!(
      type: "WelcomeNotifier", notifications_count: 1,
      idempotency_key: "WelcomeNotifier_backfill_probe", params: {},
      created_at: written_at, updated_at: written_at
    )

    ActiveRecord::Migration.suppress_messages { migration.up }
    ActiveRecord::Base.connection.schema_cache.clear!
    raw_events.reset_column_information
    Noticed::Event.reset_column_information

    expect(raw_events.find(event.id).dispatched_at).to be_within(1.second).of(written_at)

    expect { NotificationDispatchReconcileJob.perform_now }
      .not_to have_enqueued_job(Noticed::EventJob)
  end

  it "reverses" do
    ActiveRecord::Migration.suppress_messages { migration.up }
    ActiveRecord::Migration.suppress_messages { migration.down }
    ActiveRecord::Base.connection.schema_cache.clear!

    expect(ActiveRecord::Base.connection.columns("noticed_events").map(&:name))
      .not_to include("dispatched_at")
  end
end

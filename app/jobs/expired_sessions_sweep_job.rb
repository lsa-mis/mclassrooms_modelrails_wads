# frozen_string_literal: true

# Deletes sessions past their idle or absolute timeout. Housekeeping only —
# expiry is already enforced at read time in Authenticatable#find_session_by_cookie
# (expired rows resolve to nil, fail-closed), so a delayed sweep never opens a
# security window; it just keeps the table from accumulating dead rows.
#
# Batched delete_all: SQLite serializes writers; no destroy callbacks or cascades.
# See /docs/developer/architecture (Concurrency).
class ExpiredSessionsSweepJob < ApplicationJob
  queue_as :default

  def perform
    Session.expired.in_batches(of: 100, &:delete_all)
  end
end

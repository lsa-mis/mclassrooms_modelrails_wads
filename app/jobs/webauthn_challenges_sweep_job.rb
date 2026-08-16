# frozen_string_literal: true

# Deletes webauthn_challenges past a 1-day grace (#378). Challenges live for
# 5 minutes and are consumed atomically at use, but nothing ever deleted the
# rows — and the conditional-UI autofill path inserts one on EVERY load of
# the public sign-in page, so the table grows with anonymous traffic.
# Housekeeping only: expiry and single-use are both enforced at consume time
# (fail-closed), so sweep cadence is never security-critical.
#
# Batched delete_all: SQLite serializes writers; no destroy callbacks or cascades.
# See /docs/developer/architecture (Concurrency).
class WebauthnChallengesSweepJob < ApplicationJob
  queue_as :default

  # Generous versus the 5-minute TTL; covers consumed rows too (their
  # expires_at is equally in the past by then).
  GRACE = 1.day

  def perform
    WebauthnChallenge.where(expires_at: ...GRACE.ago).in_batches(of: 100, &:delete_all)
  end
end

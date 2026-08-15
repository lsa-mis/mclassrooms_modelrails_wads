# frozen_string_literal: true

# Purges direct-upload blobs that never got attached (abandoned editor
# sessions, failed form submits). Nothing else cleans these up — Rails ships
# `Blob.unattached` but no sweep — and on the production :local service they
# are permanent files on the same volume as the SQLite databases, so
# unbounded orphans are an availability risk, not just a storage bill
# (2026-08-13 SEC-7 panel).
#
# Two-day grace comfortably clears any in-flight direct-upload → attach
# window. purge_later fans file deletion out as per-blob jobs so a storage
# hiccup on one blob can't halt the sweep.
class UnattachedBlobsSweepJob < ApplicationJob
  queue_as :default

  GRACE_PERIOD = 2.days

  def perform
    ActiveStorage::Blob.unattached.where(created_at: ..GRACE_PERIOD.ago).find_each(&:purge_later)
  end
end

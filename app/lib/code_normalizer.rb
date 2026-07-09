# frozen_string_literal: true

# Single source of truth for normalizing a short/facility "code" to a stable,
# comparable form: downcase, strip every non-alphanumeric character, and
# coerce a blank result to nil (`.presence`). Codes reach the DB from two
# unrelated writers — Room#facility_code_normalized (phase 1) and the
# characteristics sync's RoomCharacteristic.short_code (phase 2) — plus the
# admin-CRUD'd CharacteristicDisplayRule.short_code; phase 3 later JOINs the
# latter two by short_code, so all of them must normalize IDENTICALLY.
#
# This module exists because two hand-rolled copies of the transform had
# already drifted: the sync's copy dropped the trailing `.presence`, so an
# all-punctuation short code normalized to "" instead of nil and raised
# RecordInvalid mid-run (presence validation) — aborting the phase for every
# later room. Funnelling every caller through here keeps them equal by
# construction.
#
# Idempotent: normalize(normalize(x)) == normalize(x). That is what lets a
# find_or_initialize_by(short_code:) round-trip once callers store the
# normalized form (db/seeds/reference_data.yml, ReferenceData.seed!).
module CodeNormalizer
  module_function

  def normalize(value)
    value.to_s.downcase.gsub(/[^a-z0-9]/, "").presence
  end
end

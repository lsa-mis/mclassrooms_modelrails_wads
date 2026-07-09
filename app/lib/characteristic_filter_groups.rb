# STUB (Phase 3 Task 2) — RoomSearch#summary needs a short_code -> display-label
# lookup for the "Filters: ..." line. Task 3 owns the real implementation,
# reading normalized CharacteristicDisplayRule rows to group/label the
# characteristics filter UI. Until then this is the identity function so
# Task 2 isn't blocked on Task 3's landing.
#
# TODO(Task 3): replace with the CharacteristicDisplayRule-backed lookup and
# remove this stub file's contents (Brief §5.2/§14.5).
module CharacteristicFilterGroups
  def self.label_for(code) = code
end

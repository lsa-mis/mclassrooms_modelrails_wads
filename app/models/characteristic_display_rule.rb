class CharacteristicDisplayRule < ApplicationRecord
  include Tenanted

  # Normalize BEFORE validation (not before_save) so the transform runs ahead
  # of BOTH validators: presence then catches an all-punctuation short_code
  # that collapses to nil, and uniqueness compares normalized values — so
  # "Whtbrd>25" and "whtbrd25" are correctly rejected as one row rather than
  # slipping past the model check and only tripping the DB unique index.
  # Shares the exact transform the phase-2 characteristics sync uses to write
  # RoomCharacteristic.short_code, so phase 3's join across the two matches.
  before_validation :normalize_short_code

  validates :short_code, presence: true, uniqueness: { scope: :workspace_id }

  private

  def normalize_short_code
    self.short_code = CodeNormalizer.normalize(short_code)
  end
end

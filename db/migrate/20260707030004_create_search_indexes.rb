class CreateSearchIndexes < ActiveRecord::Migration[8.1]
  def change
    # Standalone (not external-content) FTS5 virtual tables — see Task 7
    # brief header notes 3/4: content is duplicated into the index rather
    # than referencing the base table's rowid content, and rows are
    # maintained via AR after_save/after_destroy callbacks in the same
    # transaction rather than SQL triggers (triggers don't survive the
    # :ruby schema format's dump/reload round-trip).
    create_virtual_table :room_search_index, :fts5, [
      "facility_code", "nickname", "room_number", "rmrecnbr", "building_name",
      "tokenize = 'unicode61'"
    ]
    create_virtual_table :building_search_index, :fts5, [
      "name", "nickname", "abbreviation", "tokenize = 'unicode61'"
    ]
  end
end

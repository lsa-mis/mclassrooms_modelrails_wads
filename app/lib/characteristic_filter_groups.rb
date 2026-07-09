# Grouped characteristic checkboxes for Find a Room and the glossary
# (Brief §5.2 presentation rules, D12 rules-as-data, D14 caching).
#
# Grouping is parsed from the "Category: Value" structure of
# RoomCharacteristic#description, with CharacteristicDisplayRule overrides
# layered on top (short_code join — both sides are normalized identically,
# CodeNormalizer):
#   - filterable: false        -> excluded from .filters, still in .glossary
#   - team_learning: true      -> forced into "Team Based Learning", beating
#                                 both the parsed category AND category_override
#   - category_override        -> beats the parsed category
#   - no "Category:" prefix    -> "Other" (always sorts last)
#
# Entries are alphabetized by label within a group; groups are alphabetized
# with "Other" pinned last regardless of its name's actual alpha position.
class CharacteristicFilterGroups
  CACHE_TTL = 12.hours # backstop only; the data_version key is the real invalidation

  Entry = Struct.new(:short_code, :label, :long_description, keyword_init: true)
  Group = Struct.new(:name, :entries, keyword_init: true)

  class << self
    def filters  = fetch(:filters)
    def glossary = fetch(:glossary)

    def label_for(short_code)
      labels.fetch(short_code, short_code)
    end

    # Same cache pattern as filters/glossary — no mutable class state.
    def labels = fetch(:labels)

    # Event-keyed cache stamp (D14; contradiction #4): any characteristics
    # sync write or admin display-rule edit changes this tuple.
    def data_version
      [ RoomCharacteristic.count, RoomCharacteristic.maximum(:updated_at),
        CharacteristicDisplayRule.count, CharacteristicDisplayRule.maximum(:updated_at) ]
    end

    private

    def fetch(mode)
      Rails.cache.fetch([ "characteristic_filter_groups", mode, I18n.locale, data_version ],
                        expires_in: CACHE_TTL) { build(mode) }
    end

    def build(mode)
      return build(:glossary).flat_map(&:entries).to_h { |e| [ e.short_code, e.label ] } if mode == :labels

      rules = CharacteristicDisplayRule.all.index_by(&:short_code)
      rows  = RoomCharacteristic.select(:short_code, :description, :long_description).distinct
      other = I18n.t("characteristics.groups.other")
      team  = I18n.t("characteristics.groups.team_based_learning")

      grouped = rows.each_with_object(Hash.new { |h, k| h[k] = [] }) do |row, acc|
        rule = rules[row.short_code]
        next if mode == :filters && rule && !rule.filterable
        category, label = parse(row.description)
        category = rule&.category_override.presence || category
        category = team if rule&.team_learning
        acc[category.presence || other] << Entry.new(
          short_code: row.short_code, label: label, long_description: row.long_description
        )
      end

      grouped.map { |name, entries| Group.new(name:, entries: entries.uniq.sort_by { |e| e.label.downcase }) }
             .sort_by { |g| [ g.name == other ? 1 : 0, g.name.downcase ] }
    end

    # "Category: Value" → ["Category", "Value"]; no colon → [nil, whole string].
    def parse(description)
      category, value = description.to_s.split(":", 2)
      value ? [ category.strip, value.strip ] : [ nil, description.to_s.strip ]
    end
  end
end

class ActivityLog < ApplicationRecord
  # The ledger's date window, resolved once per request from the range params.
  # A value, not an orchestrator: it answers from/to for a key and never queries.
  class Range
    KEYS    = %w[24h 7d 30d all custom].freeze
    DEFAULT = "30d"
    DAYS    = { "7d" => 7, "30d" => 30 }.freeze

    attr_reader :key, :from, :to

    def self.resolve(key:, from:, to:, zone:)
      key = KEYS.include?(key) ? key : DEFAULT
      if key == "custom"
        from_date = parse_date(from)
        to_date   = parse_date(to)
        return resolve(key: DEFAULT, from: nil, to: nil, zone: zone) unless from_date && to_date

        from_date, to_date = to_date, from_date if from_date > to_date
        new(key: key, from: zone.local(from_date.year, from_date.month, from_date.day),
                      to: zone.local(to_date.year, to_date.month, to_date.day).end_of_day)
      else
        now = zone.now
        from = case key
        when "24h" then now - 24.hours
        when "all" then nil
        else (now - DAYS.fetch(key).days).beginning_of_day
        end
        new(key: key, from: from, to: (from && now))
      end
    end

    def self.parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :parse_date

    def initialize(key:, from:, to:)
      @key, @from, @to = key, from, to
    end

    def bounded? = from.present?
    def custom?  = key == "custom"
    def all?     = key == "all"
    def from_date = from&.to_date
    def to_date   = to&.to_date
  end
end

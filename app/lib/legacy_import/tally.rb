# frozen_string_literal: true

module LegacyImport
  # What one importer did: outcome counters plus the lines the report files
  # carry. Every service returns #to_result, so the runner and the report read
  # one shape.
  class Tally
    OUTCOMES = %i[created updated replaced skipped unmatched errors].freeze

    attr_reader :counters, :unmatched_lines, :replaced_lines, :error_lines, :info_lines

    def initialize
      @counters = OUTCOMES.index_with(0)
      @unmatched_lines, @replaced_lines, @error_lines, @info_lines = [], [], [], []
    end

    def count(outcome, by = 1)
      counters[outcome] = counters.fetch(outcome) + by
    end

    def unmatched!(line) = add(:unmatched, unmatched_lines, line)
    def replaced!(line) = add(:replaced, replaced_lines, line)
    def error!(line) = add(:errors, error_lines, line)

    def to_result
      Result.success(counters:, unmatched_lines:, replaced_lines:, error_lines:, info_lines:)
    end

    private

    def add(outcome, lines, line)
      count(outcome)
      lines << line
    end
  end
end

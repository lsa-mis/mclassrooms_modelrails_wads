# frozen_string_literal: true

module LegacyImport
  # The printed counter table and the files under the report directory:
  # unmatched.txt, replaced.txt, errors.txt (one line per item, prefixed with
  # the phase) and summary.json.
  module Report
    FILES = { "unmatched.txt" => :unmatched_lines, "replaced.txt" => :replaced_lines, "errors.txt" => :error_lines }.freeze

    def self.table(result)
      results = result.payload.fetch(:results, {})
      header = format("%-14s", "PHASE") + Tally::OUTCOMES.map { |outcome| format("%10s", outcome.upcase) }.join
      rows = results.map do |name, phase|
        format("%-14s", name) + Tally::OUTCOMES.map { |outcome| format("%10d", phase.payload[:counters][outcome]) }.join
      end
      [ header, *rows, *results.values.flat_map { |phase| phase.payload[:info_lines] } ].join("\n")
    end

    def self.write(result, dir:)
      results = result.payload.fetch(:results, {})
      FileUtils.mkdir_p(dir)
      FILES.each do |file, key|
        lines = results.flat_map { |name, phase| phase.payload[key].map { |line| "#{name}\t#{line}\n" } }
        File.write(File.join(dir, file), lines.join)
      end
      File.write(File.join(dir, "summary.json"), JSON.pretty_generate(
        success: result.success?, errors: result.errors,
        counters: results.transform_values { |phase| phase.payload[:counters] }
      ))
      dir
    end
  end
end

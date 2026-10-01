# Fails a staged comment block longer than the limit when any of its lines is new.
# See /docs/developer/conventions (Inline comments: only what code cannot express).
class CommentBlockCheck
  PARSED = %w[.rb .rake .erb .js .css .yml .yaml].freeze
  FUNCTIONAL = /\A\s*(?:#!|# frozen_string_literal|# rubocop:|# typed:|# encoding|# :nodoc:|<%#\s*locals:)/
  VENDORED_PREFIXES = %w[app/components/ui/ app/form_builders/ui/].freeze
  VENDORED_ROOTS = %w[app/javascript/ app/views/shared/].freeze
  # A preview class's comments are the notes Lookbook renders, so the commenting
  # standard's limit does not apply to them (#1313).
  RENDERED_NOTES = %r{\Aspec/components/previews/.*_preview\.rb\z}

  def self.added_lines(zero_context_diff)
    zero_context_diff.scan(/^@@ -\S+ \+(\d+)(?:,(\d+))? @@/).flat_map do |start, count|
      (start.to_i...(start.to_i + (count || "1").to_i)).to_a
    end
  end

  def initialize(max_lines: 2, vendored_basenames: nil)
    @max_lines = max_lines
    @vendored_basenames = vendored_basenames
  end

  def violations(path:, source:, added_lines:)
    return [] unless PARSED.include?(File.extname(path)) && !vendored?(path) && !path.match?(RENDERED_NOTES)

    added = added_lines.to_a
    blocks(comment_line_numbers(source, File.extname(path)))
      .select { |block| block.size > @max_lines && added.any? { |n| block.cover?(n) } }
  end

  private

  def vendored?(path)
    return true if VENDORED_PREFIXES.any? { |prefix| path.start_with?(prefix) }

    VENDORED_ROOTS.any? { |root| path.start_with?(root) } && vendored_basenames.include?(File.basename(path))
  end

  # Derived from the installed gem so a newly vendored file needs no edit here.
  def vendored_basenames
    @vendored_basenames ||= begin
      gem_dir = Gem.loaded_specs["modelrails_ui"]&.full_gem_path
      gem_dir ? Dir["#{gem_dir}/lib/generators/**/templates/**/*"].map { |f| File.basename(f, ".tt") }.to_set : Set.new
    end
  end

  def comment_line_numbers(source, ext)
    case ext
    when ".erb" then delimited(source, "<%#", "%>")
    when ".css" then delimited(source, "/*", "*/")
    when ".js" then delimited(source, "/*", "*/") | prefixed(source, %r{\A\s*//})
    else prefixed(source, /\A\s*#(?!\{)/)
    end
  end

  def prefixed(source, pattern)
    source.lines.each_with_index.filter_map do |line, i|
      i + 1 if line.match?(pattern) && !line.match?(FUNCTIONAL)
    end
  end

  def delimited(source, open, close)
    inside = false
    source.lines.each_with_index.filter_map do |line, i|
      starts = !inside && line.lstrip.start_with?(open) && !line.match?(FUNCTIONAL)
      continues = inside
      inside = (starts || inside) && !line.split(open, 2).last.include?(close) if starts || inside
      i + 1 if starts || continues
    end
  end

  def blocks(numbers)
    numbers.sort.slice_when { |a, b| b != a + 1 }.map { |run| run.first..run.last }
  end
end

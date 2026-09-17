# frozen_string_literal: true

require "prism"

# Shared source-text scanning for the code-smell fences that read app/ as text.
# Both helpers were duplicated byte-for-byte in
# spec/code_smells/notifier_recipients_block_dispatch_spec.rb and
# spec/code_smells/membership_creation_declares_actor_stance_spec.rb; a fix to
# one copy would silently leave the other scanning the old way.
#
# Text scanning is a last resort, used only where the fact being checked has no
# runtime representation — "which call sites pass what argument". A fact the
# app already carries (a class attribute, a declared constant) is read off the
# object instead.
module SourceScanning
  # Blanks every real comment via Prism's own comment list when the source
  # is valid Ruby on its own (every .rb file scanned below) — exact, unlike
  # a hand-rolled quote tracker, so a heredoc body or %-literal containing a
  # `#` is left alone. Falls back to the old per-line quote scanner for a
  # .erb template (also scanned here), which Prism can't parse as Ruby.
  # Bytes are overwritten with spaces, not deleted, so line count and offsets
  # match the source exactly.
  def without_comments(source)
    result = Prism.parse(source)
    return blank_comments(source, result.comments) if result.errors.empty?

    source.lines.map { |line| strip_trailing_comment(line) }.join
  end

  # Index just past the ")" closing the "(" at open_index, or nil when the
  # parentheses never balance. Lets a scanner read a full argument list that
  # contains nested calls and spans lines.
  def balanced_end(source, open_index)
    depth = 0
    index = open_index
    while index < source.length
      case source[index]
      when "(" then depth += 1
      when ")"
        depth -= 1
        return index + 1 if depth.zero?
      end
      index += 1
    end
    nil
  end

  private

  def blank_comments(source, comments)
    bytes = source.b
    comments.each do |comment|
      loc = comment.location
      bytes[loc.start_offset...loc.end_offset] = " " * (loc.end_offset - loc.start_offset)
    end
    bytes.force_encoding(source.encoding)
  end

  def strip_trailing_comment(line)
    return "\n" if line.lstrip.start_with?("#")

    quote = nil
    line.each_char.with_index do |char, index|
      if quote
        quote = nil if char == quote && line[index - 1] != "\\"
      elsif char == '"' || char == "'"
        quote = char
      elsif char == "#"
        return "#{line[0...index]}\n"
      end
    end
    line
  end
end

RSpec.configure do |config|
  config.include SourceScanning
end

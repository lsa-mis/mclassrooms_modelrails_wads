# frozen_string_literal: true

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
  # Blank comment lines rather than deleting them, so reported line numbers
  # still match the real file — and so a comment quoting the scanned shape
  # isn't scanned as an occurrence of it.
  def without_comments(source)
    source.lines.map { |line| line.lstrip.start_with?("#") ? "\n" : line }.join
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
end

RSpec.configure do |config|
  config.include SourceScanning
end

require "rails_helper"

# AGENTS.md §Testing: a spec never reaches an object's private surface with
# `send`. A private method is not a contract — a spec that pins one either
# duplicates a public-surface example (delete it), names a real contract the
# object should expose (promote it), or can be said publicly (rewrite it).
# #900 closed all 12 app-code sites; this guard keeps the count at zero.
#
# The exemption is a property of the file's SUBJECT, not of a line: a spec
# whose subject IS the test harness (its private surface is the thing under
# test) belongs in `allowed_sends` below, with its reason and its exact count.
# There is deliberately no inline `# allow-send:` marker — an inline disable
# moves the decision out of review and into the diff being reviewed.
RSpec.describe "Code smell: no `send` into private surfaces from specs" do
  # Locals, not constants: a constant here lands on Object, where another
  # spec file's same-named constant clobbers it whenever CI shards both into
  # one worker (the ALLOWED collision that broke CI on 2026-08-14).
  #
  # Two arms, because the two spellings have different false-positive risks:
  #
  #   `\.(?:send|__send__)\b` — an explicit receiver. Always a smell in a
  #   spec: `obj.send(...)` exists to bypass visibility. `__send__` is the
  #   evasion door (#900's own grep missed it) and `public_send` is excluded
  #   by construction — the `.` must sit immediately before `send`.
  #
  #   bare `send`/`__send__` followed by a SYMBOL LITERAL — implicit self,
  #   i.e. the example group. `send(:some_private_helper)` is the same bypass
  #   written without a receiver, while `send(renderer, "…")` — dispatching a
  #   let-bound helper name, as spec/components/ui/trigger_floor_spec.rb:26
  #   does — reaches nothing private and passes here by construction rather
  #   than by a blanket file exemption.
  #
  # The documented hole, so nobody mistakes it for coverage: a receiverless
  # send whose argument is a VARIABLE is invisible here by design — that is
  # exactly how the helper dispatch above passes — so a private method name
  # held in a variable and sent to self escapes the guard. Closing it would
  # cost every legitimate helper dispatch in the suite.
  #
  # Regex, not Prism: none of the other spec/code_smells guards parse, and
  # matching their shape is worth more than this one's precision. Comment
  # lines are skipped in the scan below (this file's own prose is the reason);
  # a `send` inside a heredoc would still be a false positive. Revisit with a
  # CallNode walk if one ever appears.
  private_send = /\.(?:send|__send__)\b|(?<![.\w:])(?:send|__send__)\s*[( ]\s*:/

  # A comment is not a call. Both scans below share this so the exemption
  # counts and the offender list can never disagree about what a match is.
  offending = ->(line) { line.match?(private_send) && !line.strip.start_with?("#") }

  # path => exact count + reason. The count is the positive control: it fails
  # loudly if an exempt file is renamed, or if the pattern silently stops
  # matching what it was written to match — a floor ("at least one") would
  # pass in both cases.
  allowed_sends = {
    "spec/lib/axe_accessibility_spec.rb" => {
      sends: 8,
      reason: "subject IS the axe harness (AxeAccessibility); its private " \
              "surface is the thing under test, not application code"
    },
    "spec/bin/parallel_rspec_spec.rb" => {
      sends: 2,
      reason: "subject IS bin/parallel-rspec's own runner object — same " \
              "test-tooling exemption (ruled 2026-08-29)"
    }
  }.freeze

  it "no spec reaches a private surface with send" do
    offenders = Dir[Rails.root.join("spec/**/*.rb")].sort.flat_map do |file|
      relative = Pathname(file).relative_path_from(Rails.root).to_s
      next [] if allowed_sends.key?(relative)

      File.readlines(file).each_with_index.filter_map do |line, i|
        "#{relative}:#{i + 1}: #{line.strip}" if offending.call(line)
      end
    end

    expect(offenders).to be_empty,
      "A private method is not a contract (AGENTS.md §Testing, #900). Say it " \
      "through the public surface, promote the method, or delete the example " \
      "when a public-surface example already covers it:\n  " \
      "#{offenders.join("\n  ")}\nA spec whose SUBJECT is the test harness " \
      "belongs in allowed_sends in this spec, with its reason and exact count."
  end

  it "each exemption still holds exactly the sends it was exempted for" do
    counts = allowed_sends.to_h do |relative, _|
      path = Rails.root.join(relative)
      lines = path.exist? ? path.readlines.count { |line| offending.call(line) } : :missing_file
      [ relative, lines ]
    end

    expect(counts).to eq(allowed_sends.transform_values { |entry| entry[:sends] })
  end
end

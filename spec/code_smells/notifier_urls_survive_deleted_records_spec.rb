# frozen_string_literal: true

require "rails_helper"

# A notification row outlives the thing it points at. The digest mailer's
# `render_safe_or_placeholder` wraps RENDERING, not URL generation, so a `#url`
# that raises does not degrade to a placeholder line — it takes down the whole
# digest render for that recipient, and the notifications index with it.
#
# Two failure shapes, which is why the wrapper alone is not the fix (#920):
#
#   workspace_path(event.record.workspace)   # record gone -> NoMethodError on nil
#   edit_workspace_settings_path(event.record) # record gone -> UrlGenerationError
#
# `render_safe_or_placeholder` rescues the first and deliberately NOT the
# second — elsewhere a nil reaching a route helper is a real routing bug worth
# raising on. `present_or_gone!` converts a nil into the deletion shape BEFORE
# the helper sees it, which is what makes both land on the placeholder.
#
# #917 guarded some notifiers this way and #920 was filed against one more; in
# fact four were unguarded, the second-bug-of-class trigger for consolidating
# on a guard rather than fixing and refiling.
#
# Scanned shape: a `def url` inside app/notifiers whose body calls a `*_path`
# or `*_url` helper WITH arguments. A helper called with no arguments routes to
# a fixed destination and cannot be handed a deleted record, so it is exempt by
# construction — `settings_passkeys_path` needs no guard and should not carry
# ceremony implying it does.
RSpec.describe "Code smell: notifier urls survive a deleted record" do
  # A local, not a constant: a constant here lands on Object, where another
  # spec file's same-named constant clobbers it whenever CI shards both into
  # one worker.
  routed_with_arguments = /\b\w+_(?:path|url)\s*\(\s*[^)\s]/

  def notifier_sources
    Dir[Rails.root.join("app/notifiers/**/*.rb")]
  end

  # The body of each `def url`, keyed by "file:line". Brace-free and
  # indentation-based: every notifier in this app declares `#url` at one fixed
  # depth inside `notification_methods`, so `def url` to the matching `end` at
  # the same indentation is unambiguous.
  def url_bodies(path)
    lines = File.readlines(path)
    bodies = {}

    lines.each_with_index do |line, i|
      next unless line =~ /^(\s*)def url\b/
      indent = Regexp.last_match(1)
      closing = lines[(i + 1)..].index { |l| l.rstrip == "#{indent}end" }
      next if closing.nil?

      bodies["#{Pathname.new(path).relative_path_from(Rails.root)}:#{i + 1}"] =
        lines[(i + 1)..(i + closing)].join
    end

    bodies
  end

  it "finds url definitions to scan, so the assertions below are not vacuous" do
    found = notifier_sources.sum { |path| url_bodies(path).size }

    # Positive control. Without it, a rename of `def url` turns every
    # assertion below into a silent pass on an empty set.
    expect(found).to be >= 10
  end

  it "guards every notifier url that routes a record" do
    offenders = notifier_sources.flat_map do |path|
      url_bodies(path).filter_map do |location, body|
        next unless body.match?(routed_with_arguments)

        missing = []
        missing << "render_safe_or_placeholder" unless body.include?("render_safe_or_placeholder")
        missing << "present_or_gone!" unless body.include?("present_or_gone!")
        next if missing.empty?

        "#{location} — missing #{missing.join(' + ')}"
      end
    end

    expect(offenders).to be_empty, <<~MESSAGE
      These notifier #url definitions pass a record to a route helper without the
      deleted-record guard:

        #{offenders.join("\n  ")}

      A notification row outlives the record it points at. Wrap the body in
      `render_safe_or_placeholder` and pass each dereferenced record through
      `present_or_gone!` before it reaches the helper — the wrapper alone does
      not rescue ActionController::UrlGenerationError, which is what a bare nil
      produces.

      If the destination is genuinely fixed, call the helper with no arguments
      and this guard will exempt it.
    MESSAGE
  end
end
